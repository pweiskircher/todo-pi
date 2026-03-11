import XCTest
@testable import TodoPi

@MainActor
final class TodoCommandServiceTests: XCTestCase {
    func testCreateUpdateCompleteAndMoveTodoPersistsThroughRepository() throws {
        let tempDirectory = try makeTempDirectory()
        let fileURL = tempDirectory.appending(path: "todos.json")
        let repository = JSONTodoRepository(fileURL: fileURL)
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        let store = TodoStore(document: .empty(now: timestamp))
        let ids = IDSequence([
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        ])
        let service = TodoCommandService(
            store: store,
            repository: repository,
            now: { timestamp },
            makeID: { ids.next() }
        )

        let list = try service.createList(title: "Inbox")
        let firstTodo = try service.createTodo(in: list.id, title: "Buy milk")
        let secondTodo = try service.createTodo(in: list.id, title: "Walk dog")
        let updatedFirstTodo = try service.updateTodo(
            in: list.id,
            todoID: firstTodo.id,
            request: TodoUpdateRequest(title: "Buy oat milk", notes: .set("2 cartons"))
        )
        let completedSecondTodo = try service.completeTodo(in: list.id, todoID: secondTodo.id)
        let movedSecondTodo = try service.moveTodo(in: list.id, todoID: secondTodo.id, to: 0)

        XCTAssertEqual(updatedFirstTodo.title, "Buy oat milk")
        XCTAssertEqual(updatedFirstTodo.notes, "2 cartons")
        XCTAssertTrue(completedSecondTodo.isCompleted)
        XCTAssertEqual(movedSecondTodo.id, secondTodo.id)
        XCTAssertEqual(store.document.lists.count, 1)
        XCTAssertEqual(store.document.lists[0].todos.map(\.title), ["Walk dog", "Buy oat milk"])
        XCTAssertEqual(store.document.lists[0].todos.map(\.sortOrder), [0, 1])

        let reloaded = try repository.load()
        XCTAssertNil(reloaded.recoveryIssue)
        XCTAssertEqual(reloaded.document, store.document)
    }

    func testCreateTodoRejectsEmptyTitle() throws {
        let service = makeService()
        let list = try service.createList(title: "Inbox")

        XCTAssertThrowsError(try service.createTodo(in: list.id, title: "   ")) { error in
            XCTAssertEqual(error as? TodoCommandService.CommandError, .emptyTitle)
        }
    }

    func testUpdateListTitleAndToggleCompletionPersist() throws {
        let tempDirectory = try makeTempDirectory()
        let repository = JSONTodoRepository(fileURL: tempDirectory.appending(path: "todos.json"))
        let store = TodoStore(document: .empty())
        let service = TodoCommandService(store: store, repository: repository)

        let list = try service.createList(title: "Inbox")
        let todo = try service.createTodo(in: list.id, title: "Buy milk")

        let renamedList = try service.updateListTitle(listID: list.id, title: "Personal")
        let completedTodo = try service.setTodoCompletion(in: list.id, todoID: todo.id, isCompleted: true)
        let reopenedTodo = try service.setTodoCompletion(in: list.id, todoID: todo.id, isCompleted: false)

        XCTAssertEqual(renamedList.title, "Personal")
        XCTAssertTrue(completedTodo.isCompleted)
        XCTAssertNotNil(completedTodo.completedAt)
        XCTAssertFalse(reopenedTodo.isCompleted)
        XCTAssertNil(reopenedTodo.completedAt)
        XCTAssertEqual(store.document.lists.first?.title, "Personal")
    }

    func testCreateTodoRejectsUnknownList() {
        let service = makeService()
        let unknownListID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        XCTAssertThrowsError(try service.createTodo(in: unknownListID, title: "Buy milk")) { error in
            XCTAssertEqual(error as? TodoCommandService.CommandError, .listNotFound(unknownListID))
        }
    }

    func testStoreDoesNotChangeWhenSaveFails() throws {
        let store = TodoStore()
        let repository = FailingTodoRepository()
        let service = TodoCommandService(store: store, repository: repository)

        XCTAssertThrowsError(try service.createList(title: "Inbox"))
        XCTAssertTrue(store.document.lists.isEmpty)
    }

    private func makeService() -> TodoCommandService {
        let tempDirectory = try! makeTempDirectory()
        let repository = JSONTodoRepository(fileURL: tempDirectory.appending(path: "todos.json"))
        let store = TodoStore()
        return TodoCommandService(store: store, repository: repository)
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

private final class IDSequence {
    private var ids: [UUID]

    init(_ ids: [UUID]) {
        self.ids = ids
    }

    func next() -> UUID {
        ids.removeFirst()
    }
}

private struct FailingTodoRepository: TodoRepository {
    let fileURL = URL(fileURLWithPath: "/tmp/does-not-matter.json")

    func load() throws -> TodoRepositoryLoadResult {
        TodoRepositoryLoadResult(document: .empty(), recoveryIssue: nil)
    }

    func save(_ document: TodoDocument) throws {
        throw TodoRepositoryError.failedToSave(fileURL, underlying: CocoaError(.fileWriteUnknown))
    }
}
