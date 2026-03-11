import Combine
import Darwin
import Foundation

enum PiSessionEvent: Equatable {
    case assistantMessageChanged(String)
    case assistantMessageCompleted(String)
    case thinkingChanged(String)
    case thinkingCompleted(String)
    case toolCallChanged(key: String, text: String)
    case toolCallCompleted(key: String, text: String, isError: Bool)
    case toolExecutionChanged(key: String, text: String)
    case toolExecutionCompleted(key: String, text: String, isError: Bool)
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
    private var streamedThinkingText = ""
    private var didFinalizeAssistantMessageForCurrentTurn = false
    private var didFinalizeThinkingMessageForCurrentTurn = false
    private var activeToolCallKey: String?
    private var activeToolCallName = "unknown"
    private var activeToolCallArguments = ""
    private var activeExtensionFingerprint: String?
    private var lastNotice: String?

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
            if shouldRestartManagedProcessForConfigurationChange() {
                stop()
                break
            }
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
        if let process {
            process.terminationHandler = nil
            terminateManagedProcess(process.processIdentifier)
        }

        process = nil
        stdinHandle = nil
        bridgeServer.stop()
        failPendingResponses(with: CancellationError())
        resetStreamingState()
        activeExtensionFingerprint = nil
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
        resetStreamingState()

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
        self.activeExtensionFingerprint = launchConfiguration.extensionFingerprint

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

    private func resetStreamingState() {
        streamedAssistantText = ""
        streamedThinkingText = ""
        didFinalizeAssistantMessageForCurrentTurn = false
        didFinalizeThinkingMessageForCurrentTurn = false
        activeToolCallKey = nil
        activeToolCallName = "unknown"
        activeToolCallArguments = ""
        lastNotice = nil
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
                resetTurnCompletionState()
            case .agentEnd:
                state = .ready
            case .turnStart:
                resetTurnCompletionState()
            case let .turnEnd(role, text):
                if role == "assistant" {
                    finalizeAssistantMessage(fallbackText: text)
                }
                finalizeThinkingMessage()
            case let .messageStart(role):
                if role == "assistant" {
                    didFinalizeAssistantMessageForCurrentTurn = false
                }
            case let .messageUpdate(update):
                handleAssistantMessageUpdate(update)
            case let .messageEnd(role, text):
                if role == "assistant" {
                    finalizeAssistantMessage(fallbackText: text)
                }
                finalizeThinkingMessage()
            case let .toolExecutionStart(info):
                eventSubject.send(.toolExecutionChanged(key: info.toolCallId, text: formatToolExecutionText(prefix: "running tool", info: info)))
            case let .toolExecutionUpdate(info):
                eventSubject.send(.toolExecutionChanged(key: info.toolCallId, text: formatToolExecutionText(prefix: "running tool", info: info)))
            case let .toolExecutionEnd(info, isError):
                eventSubject.send(.toolExecutionCompleted(key: info.toolCallId, text: formatToolExecutionText(prefix: isError ? "tool failed" : "finished tool", info: info), isError: isError))
            case let .extensionError(error):
                emitSystemNotice(error)
                state = .failed(error)
            case .unknown:
                break
            }
        }
    }

    private func resetTurnCompletionState() {
        didFinalizeAssistantMessageForCurrentTurn = false
        didFinalizeThinkingMessageForCurrentTurn = false
    }

    private func handleAssistantMessageUpdate(_ event: PiAssistantMessageEvent) {
        switch event {
        case .start:
            streamedAssistantText = ""
            streamedThinkingText = ""
            resetTurnCompletionState()
        case let .textDelta(delta):
            streamedAssistantText += delta
            eventSubject.send(.assistantMessageChanged(streamedAssistantText))
        case let .textEnd(content):
            if streamedAssistantText.isEmpty, let content, !content.isEmpty {
                streamedAssistantText = content
                eventSubject.send(.assistantMessageChanged(content))
            }
        case .thinkingStart:
            streamedThinkingText = ""
            didFinalizeThinkingMessageForCurrentTurn = false
        case let .thinkingDelta(delta):
            streamedThinkingText += delta
            eventSubject.send(.thinkingChanged(streamedThinkingText))
        case let .thinkingEnd(content):
            if streamedThinkingText.isEmpty, let content, !content.isEmpty {
                streamedThinkingText = content
            }
            finalizeThinkingMessage()
        case let .toolCallStart(info):
            let key = toolCallKey(for: info)
            activeToolCallKey = key
            activeToolCallName = info.name ?? "unknown"
            activeToolCallArguments = info.argumentsText ?? ""
            eventSubject.send(.toolCallChanged(key: key, text: formatToolCallText(name: activeToolCallName, arguments: activeToolCallArguments)))
        case let .toolCallDelta(info, delta):
            let key = toolCallKey(for: info)
            activeToolCallKey = key
            if let name = info.name {
                activeToolCallName = name
            }
            activeToolCallArguments += delta
            eventSubject.send(.toolCallChanged(key: key, text: formatToolCallText(name: activeToolCallName, arguments: activeToolCallArguments)))
        case let .toolCallEnd(info):
            let key = toolCallKey(for: info)
            let name = info.name ?? activeToolCallName
            let arguments = info.argumentsText ?? activeToolCallArguments
            eventSubject.send(.toolCallCompleted(key: key, text: formatToolCallText(name: name, arguments: arguments), isError: false))
            activeToolCallKey = nil
            activeToolCallName = "unknown"
            activeToolCallArguments = ""
        case let .done(reason):
            if reason == "error" || reason == "aborted" {
                finalizeAssistantMessage(fallbackText: streamedAssistantText)
                finalizeThinkingMessage()
            }
        case let .error(reason):
            if let reason, !reason.isEmpty {
                emitSystemNotice("Assistant stream failed: \(reason)")
            }
            finalizeAssistantMessage(fallbackText: streamedAssistantText)
            finalizeThinkingMessage()
        case .textStart:
            break
        }
    }

    private func finalizeAssistantMessage(fallbackText: String?) {
        guard !didFinalizeAssistantMessageForCurrentTurn else {
            return
        }

        let finalText: String?
        if !streamedAssistantText.isEmpty {
            finalText = streamedAssistantText
        } else {
            let trimmedFallback = fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines)
            finalText = (trimmedFallback?.isEmpty == false) ? trimmedFallback : nil
        }

        guard let finalText else {
            streamedAssistantText = ""
            return
        }

        didFinalizeAssistantMessageForCurrentTurn = true
        eventSubject.send(.assistantMessageCompleted(finalText))
        lastNotice = nil
        streamedAssistantText = ""
    }

    private func finalizeThinkingMessage() {
        guard !didFinalizeThinkingMessageForCurrentTurn else {
            return
        }

        let trimmedText = streamedThinkingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            streamedThinkingText = ""
            return
        }

        didFinalizeThinkingMessageForCurrentTurn = true
        eventSubject.send(.thinkingCompleted(trimmedText))
        streamedThinkingText = ""
    }

    private func toolCallKey(for info: PiToolCallInfo) -> String {
        info.id ?? info.name ?? "toolcall"
    }

    private func formatToolCallText(name: String, arguments: String) -> String {
        let trimmedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedArguments.isEmpty {
            return "tool call: \(name)"
        }
        return "tool call: \(name)\n\(trimmedArguments)"
    }

    private func formatToolExecutionText(prefix: String, info: PiToolExecutionInfo) -> String {
        var lines = ["\(prefix): \(info.toolName)"]

        if let argsText = info.argsText?.trimmingCharacters(in: .whitespacesAndNewlines), !argsText.isEmpty {
            lines.append(argsText)
        }

        if let resultText = info.resultText?.trimmingCharacters(in: .whitespacesAndNewlines), !resultText.isEmpty {
            lines.append(resultText)
        }

        return lines.joined(separator: "\n")
    }

    private func shouldRestartManagedProcessForConfigurationChange() -> Bool {
        guard process != nil else {
            return false
        }

        return launchConfiguration?.extensionFingerprint != activeExtensionFingerprint
    }

    private func terminateManagedProcess(_ pid: Int32) {
        guard pid > 0, processExists(pid) else {
            return
        }

        _ = Darwin.kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(1)
        while processExists(pid), Date() < deadline {
            usleep(50_000)
        }

        if processExists(pid) {
            _ = Darwin.kill(pid, SIGKILL)
        }
    }

    private func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else {
            return false
        }

        if Darwin.kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
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

        resetStreamingState()
        activeExtensionFingerprint = nil

        if process.terminationReason == .exit && process.terminationStatus == 0 {
            state = .stopped
            failPendingResponses(with: CancellationError())
        } else {
            emitSystemNotice(statusMessage)
            state = .failed(statusMessage)
            let error = NSError(domain: "TodoPi.PiSessionManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: statusMessage])
            failPendingResponses(with: error)
        }
    }

    private func emitSystemNotice(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        guard lastNotice != trimmedText else {
            return
        }

        lastNotice = trimmedText
        eventSubject.send(.systemNotice(trimmedText))
    }

    private func failPendingResponses(with error: Error) {
        let handlers = pendingResponses.values
        pendingResponses.removeAll()
        handlers.forEach { $0(.failure(error)) }
    }
}
