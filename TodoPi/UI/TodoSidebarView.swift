import SwiftUI

struct TodoSidebarView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Lists", systemImage: "sidebar.left")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    viewModel.createList()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New List")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if viewModel.lists.isEmpty {
                ContentUnavailableView(
                    "No lists yet",
                    systemImage: "tray",
                    description: Text("Create a list to start organizing your todos.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(
                    selection: Binding(
                        get: { viewModel.selectedListID },
                        set: { viewModel.selectList(id: $0) }
                    )
                ) {
                    ForEach(viewModel.lists) { list in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.title)
                                .fontWeight(.medium)
                            Text("\(list.todos.count) todos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(list.id))
                        .contextMenu {
                            Button("New Todo") {
                                viewModel.selectList(id: list.id)
                                viewModel.createTodo()
                            }

                            Divider()

                            Button("Delete List", role: .destructive) {
                                viewModel.deleteList(id: list.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220)
    }
}
