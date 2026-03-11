import Foundation

struct PiLaunchConfiguration {
    let workingDirectoryURL: URL
    let extensionURL: URL
    let socketURL: URL
    let authToken: String
    let piCommand: String

    init(
        workingDirectoryURL: URL,
        extensionURL: URL,
        socketURL: URL,
        authToken: String,
        piCommand: String = "pi"
    ) {
        self.workingDirectoryURL = workingDirectoryURL
        self.extensionURL = extensionURL
        self.socketURL = socketURL
        self.authToken = authToken
        self.piCommand = piCommand
    }

    var executableURL: URL {
        URL(fileURLWithPath: "/usr/bin/env")
    }

    var arguments: [String] {
        [
            piCommand,
            "--mode", "rpc",
            "--no-session",
            "--no-tools",
            "--extension", extensionURL.path
        ]
    }

    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TODO_PI_SOCKET"] = socketURL.path
        environment["TODO_PI_TOKEN"] = authToken
        return environment
    }

    static func defaultExtensionURL(bundle: Bundle = .main) -> URL? {
        if let bundledURL = bundle.url(forResource: "todo-app-tools", withExtension: "ts", subdirectory: "pi-extension") {
            return bundledURL
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("pi-extension", isDirectory: true)
            .appendingPathComponent("todo-app-tools.ts", isDirectory: false)

        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        return nil
    }
}
