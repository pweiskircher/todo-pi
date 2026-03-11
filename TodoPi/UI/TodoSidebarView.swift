import SwiftUI

struct TodoSidebarView: View {
    let lists: [TodoList]
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Lists", systemImage: "sidebar.left")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if lists.isEmpty {
                ContentUnavailableView(
                    "No lists yet",
                    systemImage: "tray",
                    description: Text("Lists will appear here once the app loads saved todo data.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lists, selection: $selection) { list in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.title)
                            .fontWeight(.medium)
                        Text("\(list.todos.count) todos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(list.id))
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 220)
    }
}
