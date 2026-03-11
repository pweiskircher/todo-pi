import AppKit
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

            MainWindowSplitView(viewModel: viewModel)
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

private struct MainWindowSplitView: NSViewControllerRepresentable {
    let viewModel: MainWindowViewModel

    func makeNSViewController(context: Context) -> MainWindowSplitViewController {
        MainWindowSplitViewController(viewModel: viewModel)
    }

    func updateNSViewController(_ nsViewController: MainWindowSplitViewController, context: Context) {
        nsViewController.update(viewModel: viewModel)
    }
}

@MainActor
private final class MainWindowSplitViewController: NSSplitViewController {
    private let sidebarController = NSHostingController(rootView: AnyView(EmptyView()))
    private let listController = NSHostingController(rootView: AnyView(EmptyView()))
    private let chatController = NSHostingController(rootView: AnyView(EmptyView()))

    init(viewModel: MainWindowViewModel) {
        super.init(nibName: nil, bundle: nil)
        configureSplitItems()
        update(viewModel: viewModel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(viewModel: MainWindowViewModel) {
        sidebarController.rootView = AnyView(TodoSidebarView(viewModel: viewModel))
        listController.rootView = AnyView(TodoListView(viewModel: viewModel))
        chatController.rootView = AnyView(ChatPanelView(viewModel: viewModel.chatViewModel))
    }

    private func configureSplitItems() {
        splitView.autosaveName = NSSplitView.AutosaveName("TodoPiMainWindowSplitView")
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(viewController: sidebarController)
        sidebarItem.minimumThickness = 220
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = .defaultHigh

        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 340
        listItem.canCollapse = false
        listItem.holdingPriority = .defaultLow

        let chatItem = NSSplitViewItem(viewController: chatController)
        chatItem.minimumThickness = 320
        chatItem.canCollapse = false
        chatItem.holdingPriority = .defaultHigh

        addSplitViewItem(sidebarItem)
        addSplitViewItem(listItem)
        addSplitViewItem(chatItem)
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
