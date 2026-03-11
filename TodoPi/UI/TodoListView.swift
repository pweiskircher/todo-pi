import SwiftUI

struct TodoListView: View {
    @ObservedObject var viewModel: MainWindowViewModel

    var body: some View {
        Group {
            if let list = viewModel.selectedList {
                VStack(spacing: 0) {
                    header(for: list)

                    Divider()

                    todoListSection(for: list)

                    Divider()

                    todoEditorSection
                        .frame(height: 290)
                }
            } else {
                ContentUnavailableView(
                    "Select a list",
                    systemImage: "sidebar.left",
                    description: Text("Choose a list from the sidebar to view and edit its todos.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func todoListSection(for list: TodoList) -> some View {
        Group {
            if list.todos.isEmpty {
                ContentUnavailableView(
                    "No todos in this list",
                    systemImage: "checklist",
                    description: Text("Add a todo to start filling out this list.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(
                    selection: Binding(
                        get: { viewModel.selectedTodoID },
                        set: { viewModel.selectTodo(id: $0) }
                    )
                ) {
                    ForEach(sortedTodos(in: list)) { todo in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                viewModel.toggleCompletion(for: todo.id)
                            } label: {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
                            }
                            .buttonStyle(.borderless)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title)
                                    .lineLimit(2)
                                    .strikethrough(todo.isCompleted)
                                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)

                                if let notes = todo.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .tag(Optional(todo.id))
                        .contextMenu {
                            Button(todo.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                                viewModel.toggleCompletion(for: todo.id)
                            }

                            Divider()

                            Button("Delete Todo", role: .destructive) {
                                viewModel.deleteTodo(id: todo.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func header(for list: TodoList) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("List title", text: $viewModel.listTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .onSubmit {
                        viewModel.saveListTitle()
                    }

                Button("Save") {
                    viewModel.saveListTitle()
                }

                Button("New Todo") {
                    viewModel.createTodo()
                }
            }

            let completedCount = list.todos.filter(\.isCompleted).count
            Text("\(completedCount) of \(list.todos.count) completed")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let editorErrorDescription = viewModel.editorErrorDescription {
                Text(editorErrorDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
    }

    private var todoEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let todo = viewModel.selectedTodo {
                HStack {
                    Text("Todo Details")
                        .font(.headline)

                    Spacer()

                    if todo.isCompleted {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }

                Text("First line is the title. Everything below becomes the todo details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $viewModel.todoBodyDraft)
                    .font(.body)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    Button("Discard") {
                        viewModel.discardTodoEdits()
                    }

                    Spacer()

                    Button("Save Todo") {
                        viewModel.saveTodoBody()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            } else {
                ContentUnavailableView(
                    "Select a todo",
                    systemImage: "square.and.pencil",
                    description: Text("Pick a todo above to edit its title and details.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    private func sortedTodos(in list: TodoList) -> [TodoItem] {
        list.todos.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
