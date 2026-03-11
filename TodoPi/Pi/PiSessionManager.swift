import Combine
import Foundation

enum PiSessionEvent: Equatable {
    case assistantMessageChanged(String)
    case assistantMessageCompleted(String)
    case systemNotice(String)
}

@MainActor
protocol PiSessionManaging: AnyObject {
    var statePublisher: AnyPublisher<PiSessionManager.State, Never> { get }
    var eventPublisher: AnyPublisher<PiSessionEvent, Never> { get }

    func startIfNeeded() async throws
    func sendPrompt(_ message: String) async throws
}

@MainActor
final class PiSessionManager: ObservableObject, PiSessionManaging {
    enum State: Equatable {
        case idle
        case starting
        case ready
        case busy
        case failed(String)
        case stopped
    }

    @Published private(set) var state: State = .idle

    var statePublisher: AnyPublisher<State, Never> {
        $state.eraseToAnyPublisher()
    }

    var eventPublisher: AnyPublisher<PiSessionEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    private let launchConfiguration: PiLaunchConfiguration?
    private let bridgeServer: PiBridgeServer
    private let eventSubject = PassthroughSubject<PiSessionEvent, Never>()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutFramer = PiJSONLFramer()
    private var pendingResponses: [String: (Result<PiRPCResponse, Error>) -> Void] = [:]
    private var startupTask: Task<Void, Error>?
    private var stderrText = ""
    private var streamedAssistantText = ""

    init(
        launchConfiguration: PiLaunchConfiguration?,
        bridgeServer: PiBridgeServer
    ) {
        self.launchConfiguration = launchConfiguration
        self.bridgeServer = bridgeServer
    }

    func startIfNeeded() async throws {
        switch state {
        case .ready, .busy:
            return
        case .starting:
            if let startupTask {
                return try await startupTask.value
            }
        case .idle, .failed, .stopped:
            break
        }

        let task = Task {
            try await self.startProcess()
        }
        startupTask = task

        do {
            try await task.value
        } catch {
            startupTask = nil
            throw error
        }

        startupTask = nil
    }

    func sendPrompt(_ message: String) async throws {
        try await startIfNeeded()
        let commandID = UUID().uuidString
        let response = try await sendCommandAndAwaitResponse(PiRPCCommand.prompt(id: commandID, message: message), id: commandID)
        guard response.success else {
            let errorMessage = response.error ?? "prompt failed"
            throw NSError(domain: "TodoPi.PiSessionManager", code: 6, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinHandle = nil
        bridgeServer.stop()
        failPendingResponses(with: CancellationError())
        streamedAssistantText = ""
        state = .stopped
    }

    private func startProcess() async throws {
        guard let launchConfiguration else {
            state = .failed("pi extension resource is missing")
            throw NSError(domain: "TodoPi.PiSessionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "pi extension resource is missing"])
        }

        state = .starting
        stderrText = ""
        stdoutFramer = PiJSONLFramer()
        streamedAssistantText = ""

        if let validationError = launchConfiguration.validationError {
            state = .failed(validationError)
            throw NSError(domain: "TodoPi.PiSessionManager", code: 4, userInfo: [NSLocalizedDescriptionKey: validationError])
        }

        guard let executableURL = launchConfiguration.executableURL else {
            let message = "pi executable is unavailable"
            state = .failed(message)
            throw NSError(domain: "TodoPi.PiSessionManager", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
        }

        do {
            try bridgeServer.start()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = launchConfiguration.arguments
        process.currentDirectoryURL = launchConfiguration.workingDirectoryURL
        process.environment = launchConfiguration.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.receiveStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.receiveStderr(data)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleTermination(process)
            }
        }

        do {
            try process.run()
        } catch {
            bridgeServer.stop()
            state = .failed(error.localizedDescription)
            throw error
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting

        let startupID = UUID().uuidString
        let response = try await sendCommandAndAwaitResponse(PiRPCCommand.getCommands(id: startupID), id: startupID)
        guard response.success else {
            let message = response.error ?? "pi startup command failed"
            state = .failed(message)
            throw NSError(domain: "TodoPi.PiSessionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }

        if case .starting = state {
            state = .ready
        }
    }

    private func sendCommandAndAwaitResponse(
        _ command: [String: Any],
        id: String
    ) async throws -> PiRPCResponse {
        try sendCommand(command)

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = { result in
                continuation.resume(with: result)
            }
        }
    }

    private func sendCommand(_ command: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: command)
        guard let stdinHandle else {
            throw NSError(domain: "TodoPi.PiSessionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "pi stdin is not available"])
        }

        var framed = data
        framed.append(0x0A)
        try stdinHandle.write(contentsOf: framed)
    }

    private func receiveStdout(_ data: Data) {
        do {
            let messages = try stdoutFramer.append(data)
            for message in messages {
                handle(message)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func receiveStderr(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        stderrText += text
    }

    private func handle(_ message: PiRPCMessage) {
        switch message {
        case let .response(response):
            if let id = response.id, let handler = pendingResponses.removeValue(forKey: id) {
                handler(.success(response))
            }
        case let .event(event):
            switch event {
            case .agentStart:
                state = .busy
            case .agentEnd:
                state = .ready
            case .turnStart:
                break
            case let .turnEnd(role, text):
                if role == "assistant" {
                    finalizeAssistantMessage(fallbackText: text)
                }
            case .messageStart:
                break
            case let .messageUpdate(update):
                handleAssistantMessageUpdate(update)
            case let .messageEnd(role, text):
                if role == "assistant" {
                    finalizeAssistantMessage(fallbackText: text)
                }
            case .toolExecutionStart, .toolExecutionEnd:
                break
            case let .extensionError(error):
                eventSubject.send(.systemNotice(error))
                state = .failed(error)
            case .unknown:
                break
            }
        }
    }

    private func handleAssistantMessageUpdate(_ event: PiAssistantMessageEvent) {
        switch event {
        case .start:
            streamedAssistantText = ""
        case let .textDelta(delta):
            streamedAssistantText += delta
            eventSubject.send(.assistantMessageChanged(streamedAssistantText))
        case let .textEnd(content):
            if streamedAssistantText.isEmpty, let content, !content.isEmpty {
                streamedAssistantText = content
                eventSubject.send(.assistantMessageChanged(content))
            }
        case let .done(reason):
            if reason == "error" || reason == "aborted" {
                finalizeAssistantMessage(fallbackText: streamedAssistantText)
            }
        case let .error(reason):
            if let reason, !reason.isEmpty {
                eventSubject.send(.systemNotice("Assistant stream failed: \(reason)"))
            }
            finalizeAssistantMessage(fallbackText: streamedAssistantText)
        case .textStart, .thinkingStart, .thinkingDelta, .thinkingEnd, .toolCallStart, .toolCallDelta, .toolCallEnd:
            break
        }
    }

    private func finalizeAssistantMessage(fallbackText: String?) {
        let finalText: String?
        if !streamedAssistantText.isEmpty {
            finalText = streamedAssistantText
        } else {
            let trimmedFallback = fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines)
            finalText = (trimmedFallback?.isEmpty == false) ? trimmedFallback : nil
        }

        if let finalText {
            eventSubject.send(.assistantMessageCompleted(finalText))
        }

        streamedAssistantText = ""
    }

    private func handleTermination(_ process: Process) {
        self.process = nil
        stdinHandle = nil
        bridgeServer.stop()

        let statusMessage: String
        if !stderrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            statusMessage = "pi exited with status \(process.terminationStatus)"
        }

        streamedAssistantText = ""

        if process.terminationReason == .exit && process.terminationStatus == 0 {
            state = .stopped
            failPendingResponses(with: CancellationError())
        } else {
            eventSubject.send(.systemNotice(statusMessage))
            state = .failed(statusMessage)
            let error = NSError(domain: "TodoPi.PiSessionManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: statusMessage])
            failPendingResponses(with: error)
        }
    }

    private func failPendingResponses(with error: Error) {
        let handlers = pendingResponses.values
        pendingResponses.removeAll()
        handlers.forEach { $0(.failure(error)) }
    }
}
