import XCTest
@testable import TodoPi

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    func testSelectListKeepsExplicitSelectionWhenStoreChanges() {
        let firstList = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox")
        let secondList = makeList(id: uuid("00000000-0000-0000-0000-000000000002"), title: "Today")
        let store = TodoStore(document: TodoDocument.empty().withLists([firstList, secondList]))
        let viewModel = makeViewModel(store: store)

        viewModel.selectList(id: secondList.id)
        store.replace(with: TodoDocument.empty().withLists([
            firstList,
            secondList.withTodos([makeTodo(id: uuid("00000000-0000-0000-0000-000000000003"), title: "Buy milk")])
        ]))

        XCTAssertEqual(viewModel.selectedListID, secondList.id)
        XCTAssertEqual(viewModel.selectedList?.title, "Today")
        XCTAssertNil(viewModel.selectedTodo)
    }

    func testSelectionFallsBackToFirstListWhenCurrentSelectionDisappears() {
        let firstList = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox")
        let secondList = makeList(id: uuid("00000000-0000-0000-0000-000000000002"), title: "Today")
        let store = TodoStore(document: TodoDocument.empty().withLists([firstList, secondList]))
        let viewModel = makeViewModel(store: store)

        viewModel.selectList(id: secondList.id)
        store.replace(with: TodoDocument.empty().withLists([firstList]))

        XCTAssertEqual(viewModel.selectedListID, firstList.id)
        XCTAssertNil(viewModel.selectedTodoID)
    }

    func testSelectingListDoesNotAutoSelectTodo() {
        let todo = makeTodo(id: uuid("00000000-0000-0000-0000-000000000010"), title: "Buy milk")
        let list = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox").withTodos([todo])
        let store = TodoStore(document: TodoDocument.empty().withLists([list]))
        let viewModel = makeViewModel(store: store)

        XCTAssertEqual(viewModel.selectedListID, list.id)
        XCTAssertNil(viewModel.selectedTodoID)

        viewModel.selectList(id: list.id)

        XCTAssertNil(viewModel.selectedTodoID)
    }

    func testSaveListTitleAndTodoBodyMutateStore() throws {
        let todo = makeTodo(id: uuid("00000000-0000-0000-0000-000000000010"), title: "Buy milk")
        let list = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox").withTodos([todo])
        let store = TodoStore(document: TodoDocument.empty().withLists([list]))
        let viewModel = makeViewModel(store: store)
        viewModel.selectTodo(id: todo.id)

        viewModel.listTitleDraft = "Personal"
        viewModel.saveListTitle()

        viewModel.todoBodyDraft = "Buy oat milk\n\n2 cartons from the corner store"
        viewModel.saveTodoBody()

        XCTAssertEqual(viewModel.selectedList?.title, "Personal")
        XCTAssertEqual(viewModel.selectedTodo?.title, "Buy oat milk")
        XCTAssertEqual(viewModel.selectedTodo?.notes, "2 cartons from the corner store")
        XCTAssertNil(viewModel.editorErrorDescription)
    }

    func testToggleCompletionUpdatesSelectedTodo() {
        let todo = makeTodo(id: uuid("00000000-0000-0000-0000-000000000010"), title: "Buy milk")
        let list = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox").withTodos([todo])
        let store = TodoStore(document: TodoDocument.empty().withLists([list]))
        let viewModel = makeViewModel(store: store)
        viewModel.selectTodo(id: todo.id)

        viewModel.toggleCompletion(for: todo.id)
        XCTAssertEqual(viewModel.selectedTodo?.isCompleted, true)

        viewModel.toggleCompletion(for: todo.id)
        XCTAssertEqual(viewModel.selectedTodo?.isCompleted, false)
    }

    func testCreateAndDeleteListAndTodoUpdateSelection() {
        let store = TodoStore(document: TodoDocument.empty())
        let viewModel = makeViewModel(store: store)

        viewModel.createList()
        XCTAssertEqual(viewModel.lists.count, 1)
        XCTAssertEqual(viewModel.selectedList?.title, "New List")

        viewModel.createTodo()
        XCTAssertEqual(viewModel.selectedTodo?.title, "New Todo")

        if let todoID = viewModel.selectedTodoID {
            viewModel.deleteTodo(id: todoID)
        }
        XCTAssertNil(viewModel.selectedTodo)

        if let listID = viewModel.selectedListID {
            viewModel.deleteList(id: listID)
        }
        XCTAssertTrue(viewModel.lists.isEmpty)
        XCTAssertNil(viewModel.selectedList)
    }

    func testInlineRenameAndMoveTodosMutateStore() {
        let firstTodo = makeTodo(id: uuid("00000000-0000-0000-0000-000000000010"), title: "First")
        let secondTodo = makeTodo(id: uuid("00000000-0000-0000-0000-000000000011"), title: "Second").withSortOrder(1)
        let list = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox").withTodos([firstTodo, secondTodo])
        let store = TodoStore(document: TodoDocument.empty().withLists([list]))
        let viewModel = makeViewModel(store: store)
        viewModel.selectTodo(id: firstTodo.id)

        viewModel.renameList(id: list.id, title: "Renamed Inbox")
        viewModel.renameTodoTitle(id: firstTodo.id, title: "Renamed First")
        viewModel.moveTodos(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(viewModel.selectedList?.title, "Renamed Inbox")
        XCTAssertEqual(viewModel.selectedList?.todos.map(\.title), ["Second", "Renamed First"])
        XCTAssertEqual(viewModel.selectedList?.todos.map(\.sortOrder), [0, 1])
    }

    func testDraftEditsAutosaveAfterDebounce() async throws {
        let todo = makeTodo(id: uuid("00000000-0000-0000-0000-000000000010"), title: "Buy milk")
        let list = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox").withTodos([todo])
        let store = TodoStore(document: TodoDocument.empty().withLists([list]))
        let viewModel = makeViewModel(store: store)
        viewModel.selectTodo(id: todo.id)

        viewModel.listTitleDraft = "Personal"
        viewModel.todoBodyDraft = "Buy oat milk\n\n2 cartons"

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(viewModel.selectedList?.title, "Personal")
        XCTAssertEqual(viewModel.selectedTodo?.title, "Buy oat milk")
        XCTAssertEqual(viewModel.selectedTodo?.notes, "2 cartons")
    }

    private func makeViewModel(store: TodoStore) -> MainWindowViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let repository = JSONTodoRepository(fileURL: directory.appendingPathComponent("todos.json"))
        let commandService = TodoCommandService(store: store, repository: repository)
        return MainWindowViewModel(store: store, commandService: commandService, chatViewModel: ChatViewModel())
    }

    private func makeList(id: UUID, title: String) -> TodoList {
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        return TodoList(id: id, title: title, todos: [], createdAt: timestamp, updatedAt: timestamp)
    }

    private func makeTodo(id: UUID, title: String) -> TodoItem {
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        return TodoItem(
            id: id,
            title: title,
            notes: nil,
            isCompleted: false,
            sortOrder: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            completedAt: nil
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private extension TodoDocument {
    func withLists(_ lists: [TodoList]) -> TodoDocument {
        var copy = self
        copy.lists = lists
        return copy
    }
}

private extension TodoList {
    func withTodos(_ todos: [TodoItem]) -> TodoList {
        var copy = self
        copy.todos = todos
        return copy
    }
}

private extension TodoItem {
    func withSortOrder(_ sortOrder: Int) -> TodoItem {
        var copy = self
        copy.sortOrder = sortOrder
        return copy
    }
}
