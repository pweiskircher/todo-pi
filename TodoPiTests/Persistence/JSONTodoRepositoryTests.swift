import Foundation
import XCTest
@testable import TodoPi

final class JSONTodoRepositoryTests: XCTestCase {
    func testLoadReturnsEmptyDocumentWhenFileIsMissing() throws {
        let tempDirectory = try makeTempDirectory()
        let repository = JSONTodoRepository(fileURL: tempDirectory.appending(path: "todos.json"))

        let result = try repository.load()

        XCTAssertEqual(result.document.lists, [])
        XCTAssertNil(result.recoveryIssue)
    }

    func testLoadRecoversFromMalformedJSON() throws {
        let tempDirectory = try makeTempDirectory()
        let fileURL = tempDirectory.appending(path: "todos.json")
        try "{ not valid json }".write(to: fileURL, atomically: true, encoding: .utf8)
        let repository = JSONTodoRepository(fileURL: fileURL)

        let result = try repository.load()

        XCTAssertTrue(result.document.lists.isEmpty)
        XCTAssertEqual(result.recoveryIssue, .invalidJSON(path: fileURL.path))
    }

    func testSaveAndReloadRoundTripsTheDocument() throws {
        let tempDirectory = try makeTempDirectory()
        let fileURL = tempDirectory.appending(path: "todos.json")
        let repository = JSONTodoRepository(fileURL: fileURL)
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        let document = TodoDocument(
            schemaVersion: 1,
            lists: [
                TodoList(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    title: "Inbox",
                    todos: [
                        TodoItem(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                            title: "Buy milk",
                            notes: "2 cartons",
                            isCompleted: false,
                            sortOrder: 0,
                            createdAt: timestamp,
                            updatedAt: timestamp,
                            completedAt: nil
                        )
                    ],
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try repository.save(document)
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.document, document)
        XCTAssertNil(reloaded.recoveryIssue)
    }

    func testFailedSaveDoesNotOverwriteExistingDocument() throws {
        let tempDirectory = try makeTempDirectory()
        let fileURL = tempDirectory.appending(path: "todos.json")
        let repository = JSONTodoRepository(fileURL: fileURL)
        let originalDocument = TodoDocument.empty(now: Date(timeIntervalSince1970: 100))
        try repository.save(originalDocument)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDirectory.path)
        }

        let updatedDocument = TodoDocument.empty(now: Date(timeIntervalSince1970: 200))
        XCTAssertThrowsError(try repository.save(updatedDocument))

        let reloaded = try repository.load()
        XCTAssertEqual(reloaded.document, originalDocument)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
