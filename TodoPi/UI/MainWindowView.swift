import AppKit
import SplitView
import SwiftUI

struct MainWindowView: View {
    private enum Layout {
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarDefaultWidth: CGFloat = 260
        static let listMinWidth: CGFloat = 340
        static let chatMinWidth: CGFloat = 320
        static let chatDefaultWidth: CGFloat = 320
        static let dividerThickness: CGFloat = 1
        static let defaultSidebarFraction: CGFloat = sidebarDefaultWidth / 1100
        static let defaultContentFraction: CGFloat = (1100 - sidebarDefaultWidth - chatDefaultWidth) / (1100 - sidebarDefaultWidth)
    }

    @StateObject private var viewModel: MainWindowViewModel
    @StateObject private var sidebarFraction: FractionHolder
    @StateObject private var contentFraction: FractionHolder

    init(viewModel: MainWindowViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _sidebarFraction = StateObject(wrappedValue: FractionHolder.usingUserDefaults(Layout.defaultSidebarFraction, key: "mainWindow.sidebarFraction"))
        _contentFraction = StateObject(wrappedValue: FractionHolder.usingUserDefaults(Layout.defaultContentFraction, key: "mainWindow.contentFraction"))
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

            GeometryReader { proxy in
                outerSplit(totalWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    private func outerSplit(totalWidth: CGFloat) -> some View {
        HSplit(
            left: {
                TodoSidebarView(viewModel: viewModel)
                    .frame(minWidth: Layout.sidebarMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            },
            right: {
                GeometryReader { proxy in
                    innerSplit(availableWidth: proxy.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
        .fraction(sidebarFraction)
        .constraints(
            minPFraction: fraction(for: Layout.sidebarMinWidth, in: totalWidth),
            minSFraction: fraction(for: Layout.listMinWidth + Layout.chatMinWidth + Layout.dividerThickness, in: totalWidth),
            priority: .left
        )
        .splitter {
            Splitter.line(color: Color(nsColor: .separatorColor), visibleThickness: Layout.dividerThickness)
        }
    }

    private func innerSplit(availableWidth: CGFloat) -> some View {
        HSplit(
            left: {
                TodoListView(viewModel: viewModel)
                    .frame(minWidth: Layout.listMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            },
            right: {
                ChatPanelView(viewModel: viewModel.chatViewModel)
                    .frame(minWidth: Layout.chatMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .fraction(contentFraction)
        .constraints(
            minPFraction: fraction(for: Layout.listMinWidth, in: availableWidth),
            minSFraction: fraction(for: Layout.chatMinWidth, in: availableWidth),
            priority: .right
        )
        .splitter {
            Splitter.line(color: Color(nsColor: .separatorColor), visibleThickness: Layout.dividerThickness)
        }
    }

    private func fraction(for minWidth: CGFloat, in totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else {
            return 0.5
        }

        let clamped = min(max(minWidth / totalWidth, 0), 0.9)
        return clamped
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
