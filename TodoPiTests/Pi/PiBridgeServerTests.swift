import XCTest
@testable import TodoPi

@MainActor
final class PiBridgeServerTests: XCTestCase {
    func testProcessRequestDataRejectsInvalidAuthToken() throws {
        let server = PiBridgeServer(
            socketURL: tempSocketURL(),
            authToken: "secret"
        ) { _ in
            XCTFail("Request handler should not be called for invalid tokens")
            return .success()
        }

        let request = PiBridgeRequest(token: "wrong", tool: "getLists", arguments: [:])
        let response = try decode(server.processRequestData(try JSONEncoder().encode(request)))

        XCTAssertEqual(response, .failure(code: "unauthorized", message: "invalid auth token"))
    }

    func testMissingArgumentsFieldDefaultsToEmptyDictionary() throws {
        let server = PiBridgeServer(
            socketURL: tempSocketURL(),
            authToken: "secret"
        ) { request in
            XCTAssertEqual(request.tool, "getLists")
            XCTAssertEqual(request.arguments, [:])
            return .success(.array([]))
        }

        let requestData = Data("{\"token\":\"secret\",\"tool\":\"getLists\"}".utf8)
        let response = try decode(server.processRequestData(requestData))

        XCTAssertEqual(response, .success(.array([])))
    }

    func testProcessRequestDataReturnsUnsupportedToolFailure() throws {
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        let store = TodoStore(document: .empty(now: timestamp))
        let repository = JSONTodoRepository(fileURL: tempDirectory().appending(path: "todos.json"))
        let commandService = TodoCommandService(store: store, repository: repository, now: { timestamp })
        let server = PiBridgeServer(
            socketURL: tempSocketURL(),
            authToken: "secret",
            store: store,
            commandService: commandService
        )

        let request = PiBridgeRequest(token: "secret", tool: "unknownTool", arguments: [:])
        let response = try decode(server.processRequestData(try JSONEncoder().encode(request)))

        XCTAssertEqual(response, .failure(code: "unsupported_tool", message: "Unsupported tool: unknownTool"))
    }

    func testProcessRequestDataDispatchesCreateList() throws {
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        let store = TodoStore(document: .empty(now: timestamp))
        let repository = JSONTodoRepository(fileURL: tempDirectory().appending(path: "todos.json"))
        let commandService = TodoCommandService(
            store: store,
            repository: repository,
            now: { timestamp },
            makeID: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
        )
        let server = PiBridgeServer(
            socketURL: tempSocketURL(),
            authToken: "secret",
            store: store,
            commandService: commandService
        )

        let request = PiBridgeRequest(
            token: "secret",
            tool: "createList",
            arguments: ["title": .string("Inbox")]
        )
        let response = try decode(server.processRequestData(try JSONEncoder().encode(request)))

        XCTAssertTrue(response.isSuccess)
        XCTAssertEqual(store.document.lists.first?.title, "Inbox")
    }

    private func decode(_ data: Data) throws -> PiBridgeResponse {
        let trimmed = data.last == 0x0A ? data.dropLast() : data[...]
        return try JSONDecoder().decode(PiBridgeResponse.self, from: Data(trimmed))
    }

    private func tempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func tempSocketURL() -> URL {
        tempDirectory().appendingPathComponent("bridge.sock")
    }
}
