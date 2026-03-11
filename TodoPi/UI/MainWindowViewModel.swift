import Combine
import Foundation

@MainActor
final class MainWindowViewModel: ObservableObject {
    let store: TodoStore
    let chatViewModel: ChatViewModel

    @Published private(set) var selectedListID: UUID?

    private var cancellables: Set<AnyCancellable> = []

    init(
        store: TodoStore,
        chatViewModel: ChatViewModel
    ) {
        self.store = store
        self.chatViewModel = chatViewModel
        self.selectedListID = store.document.lists.first?.id

        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        store.$document
            .map(\.lists)
            .sink { [weak self] lists in
                self?.syncSelection(with: lists)
            }
            .store(in: &cancellables)
    }

    var lists: [TodoList] {
        store.document.lists
    }

    var selectedList: TodoList? {
        guard let selectedListID else {
            return nil
        }
        return lists.first(where: { $0.id == selectedListID })
    }

    var loadIssueDescription: String? {
        store.lastLoadIssue?.errorDescription
    }

    func selectList(id: UUID?) {
        guard let id else {
            selectedListID = nil
            return
        }

        guard lists.contains(where: { $0.id == id }) else {
            return
        }

        selectedListID = id
    }

    private func syncSelection(with lists: [TodoList]) {
        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) {
            return
        }
        self.selectedListID = lists.first?.id
    }
}
