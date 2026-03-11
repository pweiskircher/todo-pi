import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel: MainWindowViewModel

    init(viewModel: MainWindowViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let loadIssueDescription = viewModel.loadIssueDescription {
                Text(loadIssueDescription)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.18))
            }

            HSplitView {
                TodoSidebarView(
                    lists: viewModel.lists,
                    selection: Binding(
                        get: { viewModel.selectedListID },
                        set: { viewModel.selectList(id: $0) }
                    )
                )
                .frame(minWidth: 220, idealWidth: 260)

                TodoListView(list: viewModel.selectedList)
                    .frame(minWidth: 340)

                ChatPanelView(viewModel: viewModel.chatViewModel)
                    .frame(minWidth: 320)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

#Preview {
    let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
    let sampleDocument = TodoDocument(
        schemaVersion: 1,
        lists: [
            TodoList(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "Inbox",
                todos: [
                    TodoItem(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                        title: "Buy milk",
                        notes: "2 cartons",
                        isCompleted: false,
                        sortOrder: 0,
                        createdAt: timestamp,
                        updatedAt: timestamp,
                        completedAt: nil
                    ),
                    TodoItem(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                        title: "Walk dog",
                        notes: nil,
                        isCompleted: true,
                        sortOrder: 1,
                        createdAt: timestamp,
                        updatedAt: timestamp,
                        completedAt: timestamp
                    )
                ],
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            TodoList(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "Work",
                todos: [],
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ],
        createdAt: timestamp,
        updatedAt: timestamp
    )
    let store = TodoStore(document: sampleDocument)
    let chatViewModel = ChatViewModel()
    chatViewModel.draftMessage = "Ask pi to clean up my inbox"
    return MainWindowView(viewModel: MainWindowViewModel(store: store, chatViewModel: chatViewModel))
}
