import XCTest
@testable import TodoPi

final class PiLaunchConfigurationTests: XCTestCase {
    func testInitializerResolvesPiFromPATH() throws {
        let fileManager = FileManager.default
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let binURL = rootURL.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: binURL, withIntermediateDirectories: true)
        let piURL = binURL.appendingPathComponent("pi", isDirectory: false)
        try makeExecutable(at: piURL)

        let configuration = PiLaunchConfiguration(
            workingDirectoryURL: rootURL,
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
            "--extension", rootURL.appendingPathComponent("todo-app-tools.ts", isDirectory: false).path
        ])
        XCTAssertEqual(configuration.environment["PATH"], binURL.path)
    }

    func testInitializerResolvesPiFromMiseInstallLocationWhenPATHDoesNotContainIt() throws {
        let fileManager = FileManager.default
        let homeURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: homeURL) }

        let piURL = homeURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("mise", isDirectory: true)
            .appendingPathComponent("installs", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("23.3.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pi", isDirectory: false)
        try fileManager.createDirectory(at: piURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeExecutable(at: piURL)

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

    private func makeExecutable(at url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
