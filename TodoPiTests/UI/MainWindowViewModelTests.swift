import XCTest
@testable import TodoPi

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    func testSelectListKeepsExplicitSelectionWhenStoreChanges() {
        let firstList = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox")
        let secondList = makeList(id: uuid("00000000-0000-0000-0000-000000000002"), title: "Today")
        let store = TodoStore(document: TodoDocument.empty().withLists([firstList, secondList]))
        let viewModel = MainWindowViewModel(store: store, chatViewModel: ChatViewModel())

        viewModel.selectList(id: secondList.id)
        store.replace(with: TodoDocument.empty().withLists([
            firstList,
            secondList.withTodos([makeTodo(id: uuid("00000000-0000-0000-0000-000000000003"), title: "Buy milk")])
        ]))

        XCTAssertEqual(viewModel.selectedListID, secondList.id)
        XCTAssertEqual(viewModel.selectedList?.title, "Today")
    }

    func testSelectionFallsBackToFirstListWhenCurrentSelectionDisappears() {
        let firstList = makeList(id: uuid("00000000-0000-0000-0000-000000000001"), title: "Inbox")
        let secondList = makeList(id: uuid("00000000-0000-0000-0000-000000000002"), title: "Today")
        let store = TodoStore(document: TodoDocument.empty().withLists([firstList, secondList]))
        let viewModel = MainWindowViewModel(store: store, chatViewModel: ChatViewModel())

        viewModel.selectList(id: secondList.id)
        store.replace(with: TodoDocument.empty().withLists([firstList]))

        XCTAssertEqual(viewModel.selectedListID, firstList.id)
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
