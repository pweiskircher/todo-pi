import SwiftUI

struct TodoListView: View {
    private enum FocusedField: Hashable {
        case listTitle
        case todoTitle
        case todoNotes
    }

    @ObservedObject var viewModel: MainWindowViewModel

    @State private var editingTodoID: UUID?
    @State private var editingTodoTitle = ""
    @State private var pendingDeleteTodo: TodoItem?
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        Group {
            if let list = viewModel.selectedList {
                VStack(spacing: 0) {
                    header(for: list)

                    if let todo = viewModel.selectedTodo {
                        Divider()

                        todoDetailsCard(for: todo)
                            .padding(16)
                    }

                    Divider()

                    todoListSection(for: list)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .listTitle, newValue != .listTitle {
                viewModel.saveListTitle()
            }

            if oldValue == .todoTitle || oldValue == .todoNotes,
               newValue != .todoTitle && newValue != .todoNotes {
                viewModel.saveTodoBody()
            }
        }
        .onDisappear {
            viewModel.persistDraftsIfNeeded()
        }
        .alert("Delete Todo?", isPresented: Binding(
            get: { pendingDeleteTodo != nil },
            set: { if !$0 { pendingDeleteTodo = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteTodo {
                    viewModel.deleteTodo(id: pendingDeleteTodo.id)
                }
                pendingDeleteTodo = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTodo = nil
            }
        } message: {
            Text("This will permanently delete \(pendingDeleteTodo?.title ?? "this todo").")
        }
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
                        row(for: todo)
                            .tag(Optional(todo.id))
                            .contextMenu {
                                Button("Rename") {
                                    beginEditing(todo)
                                }

                                Button(todo.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                                    viewModel.toggleCompletion(for: todo.id)
                                }

                                Divider()

                                Button("Delete Todo", role: .destructive) {
                                    pendingDeleteTodo = todo
                                }
                            }
                    }
                    .onMove { indices, newOffset in
                        viewModel.moveTodos(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func header(for list: TodoList) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TextField("List title", text: $viewModel.listTitleDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .focused($focusedField, equals: .listTitle)
                    .onSubmit {
                        viewModel.saveListTitle()
                    }

                Spacer()

                Button {
                    viewModel.createTodo()
                } label: {
                    Label("New Todo", systemImage: "plus")
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

    private func todoDetailsCard(for todo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if todo.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.medium))
                } else {
                    Label("Selected", systemImage: "circle.inset.filled")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.weight(.medium))
                }

                Spacer()
            }

            TextField("Todo title", text: todoTitleBinding)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($focusedField, equals: .todoTitle)
                .onSubmit {
                    viewModel.saveTodoBody()
                }

            Divider()

            TextEditor(text: todoNotesBinding)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .todoNotes)
                .frame(minHeight: 150)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var todoTitleBinding: Binding<String> {
        Binding(
            get: { currentTodoDraft().title },
            set: { updateTodoDraft(title: $0, notes: nil) }
        )
    }

    private var todoNotesBinding: Binding<String> {
        Binding(
            get: { currentTodoDraft().notes },
            set: { updateTodoDraft(title: nil, notes: $0) }
        )
    }

    private func currentTodoDraft() -> (title: String, notes: String) {
        let normalizedBody = viewModel.todoBodyDraft.replacingOccurrences(of: "\r\n", with: "\n")

        if let separatorRange = normalizedBody.range(of: "\n\n") {
            return (
                title: String(normalizedBody[..<separatorRange.lowerBound]),
                notes: String(normalizedBody[separatorRange.upperBound...])
            )
        }

        if let newlineRange = normalizedBody.range(of: "\n") {
            return (
                title: String(normalizedBody[..<newlineRange.lowerBound]),
                notes: String(normalizedBody[newlineRange.upperBound...])
            )
        }

        return (title: normalizedBody, notes: "")
    }

    private func updateTodoDraft(title: String?, notes: String?) {
        let currentDraft = currentTodoDraft()
        let nextTitle = title ?? currentDraft.title
        let nextNotes = notes ?? currentDraft.notes

        if nextNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.todoBodyDraft = nextTitle
        } else {
            viewModel.todoBodyDraft = "\(nextTitle)\n\n\(nextNotes)"
        }
    }

    @ViewBuilder
    private func row(for todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.selectTodo(id: todo.id)
                viewModel.toggleCompletion(for: todo.id)
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                if editingTodoID == todo.id {
                    TextField("Todo title", text: $editingTodoTitle)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            commitEditing(todo)
                        }
                } else {
                    Text(todo.title)
                        .lineLimit(2)
                        .strikethrough(todo.isCompleted)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                }

                if let notes = todo.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectTodo(id: todo.id)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                beginEditing(todo)
            }
        )
    }

    private func beginEditing(_ todo: TodoItem) {
        viewModel.selectTodo(id: todo.id)
        editingTodoID = todo.id
        editingTodoTitle = todo.title
    }

    private func commitEditing(_ todo: TodoItem) {
        viewModel.renameTodoTitle(id: todo.id, title: editingTodoTitle)
        editingTodoID = nil
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
