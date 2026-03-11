import Darwin
import Foundation

struct PiBridgeRequest: Codable, Equatable {
    let token: String
    let tool: String
    let arguments: [String: JSONValue]

    private enum CodingKeys: String, CodingKey {
        case token
        case tool
        case arguments
    }

    init(token: String, tool: String, arguments: [String: JSONValue]) {
        self.token = token
        self.tool = tool
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
    }
}

struct PiBridgeResponse: Codable, Equatable {
    let isSuccess: Bool
    let payload: JSONValue?
    let errorCode: String?
    let message: String?

    static func success(_ payload: JSONValue? = nil) -> PiBridgeResponse {
        PiBridgeResponse(isSuccess: true, payload: payload, errorCode: nil, message: nil)
    }

    static func failure(code: String, message: String) -> PiBridgeResponse {
        PiBridgeResponse(isSuccess: false, payload: nil, errorCode: code, message: message)
    }
}

final class PiBridgeServer {
    private let socketURL: URL
    private let authToken: String
    private let requestHandler: (PiBridgeRequest) -> PiBridgeResponse
    private let queue = DispatchQueue(label: "TodoPi.PiBridgeServer")

    private var socketFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(
        socketURL: URL,
        authToken: String,
        requestHandler: @escaping (PiBridgeRequest) -> PiBridgeResponse
    ) {
        self.socketURL = socketURL
        self.authToken = authToken
        self.requestHandler = requestHandler
    }

    convenience init(
        socketURL: URL,
        authToken: String,
        store: TodoStore,
        commandService: TodoCommandService
    ) {
        self.init(socketURL: socketURL, authToken: authToken) { request in
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    Self.handleAppRequest(request, store: store, commandService: commandService)
                }
            }

            let semaphore = DispatchSemaphore(value: 0)
            var response: PiBridgeResponse!

            Task { @MainActor in
                response = Self.handleAppRequest(request, store: store, commandService: commandService)
                semaphore.signal()
            }

            semaphore.wait()
            return response
        }
    }

    func start() throws {
        stop()
        PiDebugLog.write("Starting bridge server at \(socketURL.path)")

        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(socketURL.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        let pathBytes = socketURL.path.utf8CString
        guard pathBytes.count <= maxPathLength else {
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG))
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            let buffer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            _ = pathBytes.withUnsafeBufferPointer { pathBuffer in
                strncpy(buffer, pathBuffer.baseAddress, maxPathLength - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            let error = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }

        chmod(socketURL.path, mode_t(S_IRUSR | S_IWUSR))
        fcntl(fd, F_SETFL, O_NONBLOCK)

        guard listen(fd, SOMAXCONN) == 0 else {
            let error = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()

        socketFD = fd
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil

        if socketFD != -1 {
            PiDebugLog.write("Stopping bridge server at \(socketURL.path)")
            socketFD = -1
        }

        unlink(socketURL.path)
    }

    deinit {
        stop()
    }

    func processRequestData(_ requestData: Data) -> Data {
        let response: PiBridgeResponse
        do {
            let request = try JSONDecoder().decode(PiBridgeRequest.self, from: requestData)
            PiDebugLog.write("Bridge request tool=\(request.tool) arguments=\(describe(arguments: request.arguments))")

            if request.token != authToken {
                PiDebugLog.write("Bridge request rejected: invalid auth token for tool=\(request.tool)")
                response = .failure(code: "unauthorized", message: "invalid auth token")
            } else {
                response = requestHandler(request)
            }
        } catch {
            let rawText = String(data: requestData, encoding: .utf8) ?? "<non-utf8 request: \(requestData.count) bytes>"
            PiDebugLog.write("Bridge request decode failed: \(error.localizedDescription) raw=\(rawText.replacingOccurrences(of: authToken, with: "<redacted>"))")
            response = .failure(code: "invalid_request", message: error.localizedDescription)
        }

        PiDebugLog.write("Bridge response success=\(response.isSuccess) errorCode=\(response.errorCode ?? "nil") message=\(response.message ?? "nil")")
        let data = (try? JSONEncoder().encode(response)) ?? Data("{\"isSuccess\":false,\"errorCode\":\"encoding_failed\",\"message\":\"failed to encode response\"}".utf8)
        var framed = data
        framed.append(0x0A)
        return framed
    }

    private func acceptConnections() {
        while true {
            let clientFD = accept(socketFD, nil, nil)
            if clientFD == -1 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                return
            }

            configureClientSocket(clientFD)

            queue.async { [weak self] in
                self?.handleConnection(clientFD)
            }
        }
    }

    private func configureClientSocket(_ clientFD: Int32) {
        let flags = fcntl(clientFD, F_GETFL)
        guard flags != -1 else {
            return
        }

        _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
    }

    private func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }

        var requestData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(1)

        while Date() < deadline {
            let bytesRead = read(clientFD, &buffer, buffer.count)
            if bytesRead > 0 {
                requestData.append(buffer, count: Int(bytesRead))
                if requestData.contains(0x0A) {
                    break
                }
                continue
            }

            if bytesRead == 0 {
                break
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                usleep(10_000)
                continue
            }

            PiDebugLog.write("Bridge socket read failed errno=\(errno)")
            break
        }

        if requestData.isEmpty {
            PiDebugLog.write("Bridge connection closed without receiving request data")
        }

        guard let newlineIndex = requestData.firstIndex(of: 0x0A) else {
            let response = processRequestData(requestData)
            _ = response.withUnsafeBytes { write(clientFD, $0.baseAddress, response.count) }
            return
        }

        var line = requestData.prefix(upTo: newlineIndex)
        if line.last == 0x0D {
            line = line.dropLast()
        }

        let response = processRequestData(Data(line))
        _ = response.withUnsafeBytes { write(clientFD, $0.baseAddress, response.count) }
    }

    @MainActor
    private static func handleAppRequest(
        _ request: PiBridgeRequest,
        store: TodoStore,
        commandService: TodoCommandService
    ) -> PiBridgeResponse {
        do {
            switch request.tool {
            case "getLists":
                return .success(try jsonValue(from: store.document.lists))
            case "getTodos":
                let listID = try uuidArgument(named: "listId", from: request.arguments)
                guard let list = store.document.lists.first(where: { $0.id == listID }) else {
                    return .failure(code: "list_not_found", message: "Todo list not found")
                }
                return .success(try jsonValue(from: list.todos))
            case "createList":
                let title = try stringArgument(named: "title", from: request.arguments)
                let list = try commandService.createList(title: title)
                return .success(try jsonValue(from: list))
            case "createTodo":
                let listID = try uuidArgument(named: "listId", from: request.arguments)
                let title = try stringArgument(named: "title", from: request.arguments)
                let notes = request.arguments["notes"]?.stringValue
                let todo = try commandService.createTodo(in: listID, title: title, notes: notes)
                return .success(try jsonValue(from: todo))
            case "updateTodo":
                let listID = try uuidArgument(named: "listId", from: request.arguments)
                let todoID = try uuidArgument(named: "todoId", from: request.arguments)
                let requestBody = TodoUpdateRequest(
                    title: request.arguments["title"]?.stringValue,
                    notes: request.arguments["notes"].map { .set($0.stringValue ?? "") } ?? .preserve
                )
                let todo = try commandService.updateTodo(in: listID, todoID: todoID, request: requestBody)
                return .success(try jsonValue(from: todo))
            case "completeTodo":
                let listID = try uuidArgument(named: "listId", from: request.arguments)
                let todoID = try uuidArgument(named: "todoId", from: request.arguments)
                let todo = try commandService.completeTodo(in: listID, todoID: todoID)
                return .success(try jsonValue(from: todo))
            case "moveTodo":
                let listID = try uuidArgument(named: "listId", from: request.arguments)
                let todoID = try uuidArgument(named: "todoId", from: request.arguments)
                let destinationIndex = try intArgument(named: "destinationIndex", from: request.arguments)
                let todo = try commandService.moveTodo(in: listID, todoID: todoID, to: destinationIndex)
                return .success(try jsonValue(from: todo))
            default:
                return .failure(code: "unsupported_tool", message: "Unsupported tool: \(request.tool)")
            }
        } catch let error as TodoCommandService.CommandError {
            return .failure(code: "command_error", message: error.localizedDescription)
        } catch {
            return .failure(code: "bad_request", message: error.localizedDescription)
        }
    }

    private static func stringArgument(named name: String, from arguments: [String: JSONValue]) throws -> String {
        guard let value = arguments[name]?.stringValue else {
            throw NSError(domain: "TodoPi.PiBridgeServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing string argument: \(name)"])
        }
        return value
    }

    private static func uuidArgument(named name: String, from arguments: [String: JSONValue]) throws -> UUID {
        let value = try stringArgument(named: name, from: arguments)
        guard let uuid = UUID(uuidString: value) else {
            throw NSError(domain: "TodoPi.PiBridgeServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID for \(name)"])
        }
        return uuid
    }

    private static func intArgument(named name: String, from arguments: [String: JSONValue]) throws -> Int {
        guard let value = arguments[name]?.intValue else {
            throw NSError(domain: "TodoPi.PiBridgeServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing integer argument: \(name)"])
        }
        return value
    }

    private func describe(arguments: [String: JSONValue]) -> String {
        guard !arguments.isEmpty else {
            return "{}"
        }

        if let data = try? JSONEncoder().encode(arguments),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        return "<unencodable arguments>"
    }

    private static func jsonValue<T: Encodable>(from value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue(any: object)
    }
}
