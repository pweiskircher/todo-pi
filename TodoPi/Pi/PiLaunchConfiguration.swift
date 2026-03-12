import CryptoKit
import Foundation

struct TodoPiBridgeRuntimeInfo: Codable, Equatable {
    let version: Int
    let socketPath: String
    let token: String
    let processIdentifier: Int32
    let updatedAt: Date
}

struct PiLaunchConfiguration {
    let workingDirectoryURL: URL
    let configDirectoryURL: URL?
    let extensionURL: URL
    let socketURL: URL
    let authToken: String
    let piCommand: String
    let executableURL: URL?
    let validationError: String?
    let extensionFingerprint: String?

    private let baseEnvironment: [String: String]

    init(
        workingDirectoryURL: URL,
        configDirectoryURL: URL? = nil,
        extensionURL: URL,
        socketURL: URL,
        authToken: String,
        piCommand: String = "pi",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.workingDirectoryURL = workingDirectoryURL
        self.configDirectoryURL = configDirectoryURL
        self.extensionURL = extensionURL
        self.socketURL = socketURL
        self.authToken = authToken
        self.piCommand = piCommand
        self.baseEnvironment = environment
        self.extensionFingerprint = Self.extensionFingerprint(for: extensionURL)

        if let executableURL = Self.resolveExecutableURL(
            command: piCommand,
            environment: environment,
            homeDirectoryURL: homeDirectoryURL,
            fileManager: fileManager
        ) {
            self.executableURL = executableURL
            self.validationError = nil
        } else {
            self.executableURL = nil
            self.validationError = Self.missingExecutableErrorDescription(
                command: piCommand,
                homeDirectoryURL: homeDirectoryURL
            )
        }
    }

    var arguments: [String] {
        [
            "--mode", "rpc",
            "--no-session",
            "--no-tools",
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--extension", extensionURL.path
        ]
    }

    var environment: [String: String] {
        var environment = baseEnvironment
        if let executableURL {
            environment["PATH"] = Self.prependPathComponent(
                executableURL.deletingLastPathComponent().path,
                to: environment["PATH"]
            )
        }
        if let configDirectoryURL {
            environment["PI_CODING_AGENT_DIR"] = configDirectoryURL.path
        }
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

    static func defaultWorkingDirectoryURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> URL {
        let baseURL = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("TodoPi", isDirectory: true)
            .appendingPathComponent("pi-runtime", isDirectory: true)
    }

    static func defaultConfigDirectoryURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> URL {
        let baseURL = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("TodoPi", isDirectory: true)
            .appendingPathComponent("pi-agent", isDirectory: true)
    }

    static func defaultBridgeRuntimeInfoURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> URL {
        let baseURL = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("TodoPi", isDirectory: true)
            .appendingPathComponent("bridge-runtime.json", isDirectory: false)
    }

    private static func resolveExecutableURL(
        command: String,
        environment: [String: String],
        homeDirectoryURL: URL,
        fileManager: FileManager
    ) -> URL? {
        let expandedCommand = NSString(string: command).expandingTildeInPath
        if expandedCommand.contains("/") {
            let url = URL(fileURLWithPath: expandedCommand).standardizedFileURL
            guard fileManager.isExecutableFile(atPath: url.path), !isShimURL(url, homeDirectoryURL: homeDirectoryURL) else {
                return nil
            }
            return url
        }

        var candidates: [URL] = []
        var seenPaths: Set<String> = []

        func appendCandidate(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { return }
            candidates.append(URL(fileURLWithPath: path))
        }

        environment["PATH"]?
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .forEach { directory in
                appendCandidate(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(command, isDirectory: false))
            }

        [
            homeDirectoryURL.appendingPathComponent(".local/bin", isDirectory: true).appendingPathComponent(command, isDirectory: false),
            homeDirectoryURL.appendingPathComponent(".local/share/mise/shims", isDirectory: true).appendingPathComponent(command, isDirectory: false),
            homeDirectoryURL.appendingPathComponent(".asdf/shims", isDirectory: true).appendingPathComponent(command, isDirectory: false),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true).appendingPathComponent(command, isDirectory: false),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true).appendingPathComponent(command, isDirectory: false)
        ].forEach(appendCandidate)

        miseInstallCandidates(command: command, homeDirectoryURL: homeDirectoryURL, fileManager: fileManager)
            .forEach(appendCandidate)

        return candidates.first {
            fileManager.isExecutableFile(atPath: $0.path) && !isShimURL($0, homeDirectoryURL: homeDirectoryURL)
        }
    }

    private static func isShimURL(_ url: URL, homeDirectoryURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let knownShimDirectories = [
            homeDirectoryURL.appendingPathComponent(".asdf/shims", isDirectory: true).path,
            homeDirectoryURL.appendingPathComponent(".local/share/mise/shims", isDirectory: true).path
        ]

        return knownShimDirectories.contains(where: { path.hasPrefix($0 + "/") || path == $0 })
    }

    private static func miseInstallCandidates(
        command: String,
        homeDirectoryURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let installsURL = homeDirectoryURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("mise", isDirectory: true)
            .appendingPathComponent("installs", isDirectory: true)

        guard let toolURLs = try? fileManager.contentsOfDirectory(
            at: installsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return toolURLs
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { toolURL -> [URL] in
                guard let versionURLs = try? fileManager.contentsOfDirectory(
                    at: toolURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else {
                    return []
                }

                return versionURLs
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                    .map {
                        $0.appendingPathComponent("bin", isDirectory: true)
                            .appendingPathComponent(command, isDirectory: false)
                    }
            }
    }

    private static func extensionFingerprint(for extensionURL: URL) -> String? {
        guard let data = try? Data(contentsOf: extensionURL) else {
            return nil
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func prependPathComponent(_ component: String, to existingPath: String?) -> String {
        guard let existingPath, !existingPath.isEmpty else {
            return component
        }

        let segments = existingPath.split(separator: ":").map(String.init)
        if segments.contains(component) {
            return existingPath
        }

        return ([component] + segments).joined(separator: ":")
    }

    private static func missingExecutableErrorDescription(command: String, homeDirectoryURL: URL) -> String {
        let miseInstallsPath = homeDirectoryURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("mise", isDirectory: true)
            .appendingPathComponent("installs", isDirectory: true)
            .path

        return "Could not find \(command). GUI apps do not always inherit your shell PATH. Checked PATH and common install locations, including \(miseInstallsPath)."
    }
}
