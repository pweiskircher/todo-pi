import SwiftUI

private enum MainWindowPane: Hashable {
    case sidebar
    case chat
}

private enum MainWindowLayout {
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarDefaultWidth: CGFloat = 260
    static let listMinWidth: CGFloat = 340
    static let chatMinWidth: CGFloat = 320
    static let chatDefaultWidth: CGFloat = 320
}

private struct PaneWidthPreferenceKey: PreferenceKey {
    static let defaultValue: [MainWindowPane: CGFloat] = [:]

    static func reduce(value: inout [MainWindowPane: CGFloat], nextValue: () -> [MainWindowPane: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MainWindowView: View {
    @StateObject private var viewModel: MainWindowViewModel
    @AppStorage("mainWindow.sidebarWidth") private var storedSidebarWidth = MainWindowLayout.sidebarDefaultWidth
    @AppStorage("mainWindow.chatWidth") private var storedChatWidth = MainWindowLayout.chatDefaultWidth

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
                TodoSidebarView(viewModel: viewModel)
                    .frame(
                        minWidth: MainWindowLayout.sidebarMinWidth,
                        idealWidth: clampedSidebarWidth
                    )
                    .background(widthReader(for: .sidebar))

                TodoListView(viewModel: viewModel)
                    .frame(minWidth: MainWindowLayout.listMinWidth)

                ChatPanelView(viewModel: viewModel.chatViewModel)
                    .frame(
                        minWidth: MainWindowLayout.chatMinWidth,
                        idealWidth: clampedChatWidth
                    )
                    .background(widthReader(for: .chat))
            }
            .onPreferenceChange(PaneWidthPreferenceKey.self) { widths in
                if let sidebarWidth = widths[.sidebar] {
                    saveWidth(sidebarWidth, for: .sidebar)
                }

                if let chatWidth = widths[.chat] {
                    saveWidth(chatWidth, for: .chat)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    private var clampedSidebarWidth: CGFloat {
        max(MainWindowLayout.sidebarMinWidth, storedSidebarWidth)
    }

    private var clampedChatWidth: CGFloat {
        max(MainWindowLayout.chatMinWidth, storedChatWidth)
    }

    @ViewBuilder
    private func widthReader(for pane: MainWindowPane) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: PaneWidthPreferenceKey.self, value: [pane: proxy.size.width])
        }
    }

    private func saveWidth(_ width: CGFloat, for pane: MainWindowPane) {
        let clampedWidth: CGFloat
        switch pane {
        case .sidebar:
            clampedWidth = max(MainWindowLayout.sidebarMinWidth, width)
            guard abs(clampedWidth - storedSidebarWidth) > 1 else {
                return
            }
            storedSidebarWidth = clampedWidth

        case .chat:
            clampedWidth = max(MainWindowLayout.chatMinWidth, width)
            guard abs(clampedWidth - storedChatWidth) > 1 else {
                return
            }
            storedChatWidth = clampedWidth
        }
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
    let repository = JSONTodoRepository(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-todos.json"))
    let commandService = TodoCommandService(store: store, repository: repository)
    let chatViewModel = ChatViewModel()
    chatViewModel.draftMessage = "Ask pi to clean up my inbox"
    return MainWindowView(viewModel: MainWindowViewModel(store: store, commandService: commandService, chatViewModel: chatViewModel))
}
