import XCTest
@testable import TodoPi

final class PiLaunchConfigurationTests: XCTestCase {
    func testDefaultWorkingDirectoryURLUsesApplicationSupportSubdirectory() throws {
        let fileManager = FileManager.default
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        let workingDirectoryURL = PiLaunchConfiguration.defaultWorkingDirectoryURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )

        XCTAssertEqual(
            workingDirectoryURL.path,
            applicationSupportURL
                .appendingPathComponent("TodoPi", isDirectory: true)
                .appendingPathComponent("pi-runtime", isDirectory: true)
                .path
        )
    }

    func testDefaultConfigDirectoryURLUsesApplicationSupportSubdirectory() throws {
        let fileManager = FileManager.default
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        let configDirectoryURL = PiLaunchConfiguration.defaultConfigDirectoryURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )

        XCTAssertEqual(
            configDirectoryURL.path,
            applicationSupportURL
                .appendingPathComponent("TodoPi", isDirectory: true)
                .appendingPathComponent("pi-agent", isDirectory: true)
                .path
        )
    }

    func testDefaultBridgeRuntimeInfoURLUsesApplicationSupportSubdirectory() throws {
        let fileManager = FileManager.default
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        let runtimeInfoURL = PiLaunchConfiguration.defaultBridgeRuntimeInfoURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )

        XCTAssertEqual(
            runtimeInfoURL.path,
            applicationSupportURL
                .appendingPathComponent("TodoPi", isDirectory: true)
                .appendingPathComponent("bridge-runtime.json", isDirectory: false)
                .path
        )
    }

    func testExtensionFingerprintReflectsFileContents() throws {
        let fileManager = FileManager.default
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let extensionURL = rootURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false)
        try "export default {}\n".write(to: extensionURL, atomically: true, encoding: .utf8)

        let firstConfiguration = PiLaunchConfiguration(
            workingDirectoryURL: rootURL,
            extensionURL: extensionURL,
            socketURL: rootURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectoryURL: rootURL,
            fileManager: fileManager
        )

        try "export default { changed: true }\n".write(to: extensionURL, atomically: true, encoding: .utf8)

        let secondConfiguration = PiLaunchConfiguration(
            workingDirectoryURL: rootURL,
            extensionURL: extensionURL,
            socketURL: rootURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectoryURL: rootURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(firstConfiguration.extensionFingerprint)
        XCTAssertNotNil(secondConfiguration.extensionFingerprint)
        XCTAssertNotEqual(firstConfiguration.extensionFingerprint, secondConfiguration.extensionFingerprint)
    }

    func testInitializerResolvesPiFromPATH() throws {
        let fileManager = FileManager.default
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: binURL, withIntermediateDirectories: true)
        let piURL = binURL.appendingPathComponent("pi", isDirectory: false)
        try makeExecutable(at: piURL)

        let configDirectoryURL = rootURL.appendingPathComponent("pi-agent", isDirectory: true)
        let configuration = PiLaunchConfiguration(
            workingDirectoryURL: rootURL,
            configDirectoryURL: configDirectoryURL,
            extensionURL: rootURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false),
            socketURL: rootURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": binURL.path],
            homeDirectoryURL: rootURL,
            fileManager: fileManager
        )

        XCTAssertEqual(configuration.executableURL?.path, piURL.path)
        XCTAssertNil(configuration.validationError)
        XCTAssertEqual(configuration.arguments, [
            "--mode", "rpc",
            "--no-session",
            "--no-tools",
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--extension", rootURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false).path
        ])
        XCTAssertEqual(configuration.environment["PATH"], binURL.path)
        XCTAssertEqual(configuration.environment["PI_CODING_AGENT_DIR"], configDirectoryURL.path)
    }

    func testInitializerResolvesPiFromMiseInstallLocationWhenPATHDoesNotContainIt() throws {
        let fileManager = FileManager.default
        let homeURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: homeURL) }

        let piURL = try makeMiseInstalledPi(at: homeURL)

        let configuration = PiLaunchConfiguration(
            workingDirectoryURL: homeURL,
            extensionURL: homeURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false),
            socketURL: homeURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectoryURL: homeURL,
            fileManager: fileManager
        )

        XCTAssertEqual(configuration.executableURL?.path, piURL.path)
        XCTAssertNil(configuration.validationError)
        XCTAssertTrue(configuration.environment["PATH"]?.contains(piURL.deletingLastPathComponent().path) == true)
    }

    func testInitializerPrefersRealMiseInstallOverAsdfShimInPATH() throws {
        let fileManager = FileManager.default
        let homeURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: homeURL) }

        let shimURL = homeURL
            .appendingPathComponent(".asdf", isDirectory: true)
            .appendingPathComponent("shims", isDirectory: true)
            .appendingPathComponent("pi", isDirectory: false)
        try fileManager.createDirectory(at: shimURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeExecutable(at: shimURL)

        let piURL = try makeMiseInstalledPi(at: homeURL)

        let configuration = PiLaunchConfiguration(
            workingDirectoryURL: homeURL,
            extensionURL: homeURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false),
            socketURL: homeURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": shimURL.deletingLastPathComponent().path],
            homeDirectoryURL: homeURL,
            fileManager: fileManager
        )

        XCTAssertEqual(configuration.executableURL?.path, piURL.path)
        XCTAssertNil(configuration.validationError)
    }

    func testInitializerRejectsShimOnlyResolution() throws {
        let fileManager = FileManager.default
        let homeURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: homeURL) }

        let shimURL = homeURL
            .appendingPathComponent(".asdf", isDirectory: true)
            .appendingPathComponent("shims", isDirectory: true)
            .appendingPathComponent("pi", isDirectory: false)
        try fileManager.createDirectory(at: shimURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeExecutable(at: shimURL)

        let configuration = PiLaunchConfiguration(
            workingDirectoryURL: homeURL,
            extensionURL: homeURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false),
            socketURL: homeURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": shimURL.deletingLastPathComponent().path],
            homeDirectoryURL: homeURL,
            fileManager: fileManager
        )

        XCTAssertNil(configuration.executableURL)
        XCTAssertNotNil(configuration.validationError)
    }

    func testInitializerReportsHelpfulErrorWhenPiCannotBeFound() throws {
        let fileManager = FileManager.default
        let homeURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: homeURL) }

        let configuration = PiLaunchConfiguration(
            workingDirectoryURL: homeURL,
            extensionURL: homeURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false),
            socketURL: homeURL.appendingPathComponent("todo.sock", isDirectory: false),
            authToken: "token",
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectoryURL: homeURL,
            fileManager: fileManager
        )
        let expectedMisePath = homeURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("mise", isDirectory: true)
            .appendingPathComponent("installs", isDirectory: true)
            .path

        XCTAssertNil(configuration.executableURL)
        XCTAssertEqual(
            configuration.validationError,
            "Could not find pi. GUI apps do not always inherit your shell PATH. Checked PATH and common install locations, including \(expectedMisePath)."
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func makeMiseInstalledPi(at homeURL: URL) throws -> URL {
        let piURL = homeURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("mise", isDirectory: true)
            .appendingPathComponent("installs", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("23.3.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pi", isDirectory: false)
        try FileManager.default.createDirectory(at: piURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeExecutable(at: piURL)
        return piURL
    }

    private func makeExecutable(at url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
