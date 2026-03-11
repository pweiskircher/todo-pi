import Combine
import Foundation

@MainActor
final class PiSessionManager: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case ready
        case busy
        case failed(String)
        case stopped
    }

    @Published private(set) var state: State = .idle

    private let launchConfiguration: PiLaunchConfiguration?
    private let bridgeServer: PiBridgeServer

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutFramer = PiJSONLFramer()
    private var pendingResponses: [String: (Result<PiRPCResponse, Error>) -> Void] = [:]
    private var startupTask: Task<Void, Error>?
    private var stderrText = ""

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
        _ = try await sendCommandAndAwaitResponse(PiRPCCommand.prompt(id: commandID, message: message), id: commandID)
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinHandle = nil
        bridgeServer.stop()
        failPendingResponses(with: CancellationError())
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
        process.executableURL = launchConfiguration.executableURL
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
            case let .extensionError(error):
                state = .failed(error)
            case .turnStart, .turnEnd, .messageStart, .messageEnd, .toolExecutionStart, .toolExecutionEnd, .unknown:
                break
            }
        }
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

        if process.terminationReason == .exit && process.terminationStatus == 0 {
            state = .stopped
            failPendingResponses(with: CancellationError())
        } else {
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
