import SwiftUI

struct TodoListView: View {
    let list: TodoList?

    var body: some View {
        Group {
            if let list {
                VStack(alignment: .leading, spacing: 16) {
                    header(for: list)

                    if list.todos.isEmpty {
                        ContentUnavailableView(
                            "No todos in this list",
                            systemImage: "checklist",
                            description: Text("Todos will appear here once the app starts creating or loading them.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(sortedTodos(in: list)) { todo in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isCompleted ? .green : .secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(todo.title)
                                        .strikethrough(todo.isCompleted)
                                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)

                                    if let notes = todo.notes {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.inset)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a list",
                    systemImage: "sidebar.left",
                    description: Text("Choose a list from the sidebar to view its todos.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(for list: TodoList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(list.title)
                .font(.title2)
                .fontWeight(.semibold)

            let completedCount = list.todos.filter(\.isCompleted).count
            Text("\(completedCount) of \(list.todos.count) completed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
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
