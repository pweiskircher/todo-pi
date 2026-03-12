import SwiftUI

struct TodoSidebarView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    @State private var editingListID: UUID?
    @State private var editingListTitle = ""
    @State private var pendingDeleteList: TodoList?
    @State private var sidebarSelection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if viewModel.lists.isEmpty {
                ContentUnavailableView(
                    "No lists yet",
                    systemImage: "tray",
                    description: Text("Create a list to start organizing your todos.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $sidebarSelection) {
                    ForEach(viewModel.lists) { list in
                        row(for: list)
                            .tag(Optional(list.id))
                            .contextMenu {
                                Button("Rename") {
                                    beginEditing(list)
                                }

                                Button("New Todo") {
                                    viewModel.selectList(id: list.id)
                                    viewModel.createTodo()
                                }

                                Divider()

                                Button("Delete List", role: .destructive) {
                                    pendingDeleteList = list
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220)
        .onAppear {
            sidebarSelection = viewModel.selectedListID
        }
        .onChange(of: viewModel.selectedListID) { _, newValue in
            if sidebarSelection != newValue {
                sidebarSelection = newValue
            }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard newValue != viewModel.selectedListID else {
                return
            }

            DispatchQueue.main.async {
                viewModel.selectList(id: newValue)
            }
        }
        .alert("Delete List?", isPresented: Binding(
            get: { pendingDeleteList != nil },
            set: { if !$0 { pendingDeleteList = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteList {
                    viewModel.deleteList(id: pendingDeleteList.id)
                }
                pendingDeleteList = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteList = nil
            }
        } message: {
            Text("This will permanently delete \(pendingDeleteList?.title ?? "this list") and all of its todos.")
        }
    }

    private var header: some View {
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
            .buttonStyle(.borderless)
            .help("New List")
        }
        .padding(16)
    }

    @ViewBuilder
    private func row(for list: TodoList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if editingListID == list.id {
                TextField("List title", text: $editingListTitle)
                    .textFieldStyle(.plain)
                    .fontWeight(.medium)
                    .onSubmit {
                        commitEditingList(list)
                    }
            } else {
                Text(list.title)
                    .fontWeight(.medium)
            }

            Text("\(list.todos.count) todos")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func beginEditing(_ list: TodoList) {
        viewModel.selectList(id: list.id)
        editingListID = list.id
        editingListTitle = list.title
    }

    private func commitEditingList(_ list: TodoList) {
        viewModel.renameList(id: list.id, title: editingListTitle)
        editingListID = nil
    }
}
