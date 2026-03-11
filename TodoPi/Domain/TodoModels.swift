import Foundation

struct TodoDocument: Codable, Equatable {
    var schemaVersion: Int
    var lists: [TodoList]
    var createdAt: Date
    var updatedAt: Date

    static func empty(now: Date = Date()) -> TodoDocument {
        TodoDocument(
            schemaVersion: 1,
            lists: [],
            createdAt: now,
            updatedAt: now
        )
    }
}

struct TodoList: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var todos: [TodoItem]
    var createdAt: Date
    var updatedAt: Date
}

struct TodoItem: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var notes: String?
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

struct TodoUpdateRequest: Equatable {
    enum NotesUpdate: Equatable {
        case preserve
        case set(String)
        case clear
    }

    var title: String?
    var notes: NotesUpdate

    init(title: String? = nil, notes: NotesUpdate = .preserve) {
        self.title = title
        self.notes = notes
    }
}
