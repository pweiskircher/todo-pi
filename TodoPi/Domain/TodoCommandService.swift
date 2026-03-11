import Foundation

@MainActor
final class TodoCommandService {
    enum CommandError: LocalizedError, Equatable {
        case emptyTitle
        case listNotFound(UUID)
        case todoNotFound(UUID)
        case invalidDestinationIndex(Int)

        var errorDescription: String? {
            switch self {
            case .emptyTitle:
                return "Todo titles and list titles must not be empty."
            case let .listNotFound(id):
                return "Todo list not found: \(id.uuidString)"
            case let .todoNotFound(id):
                return "Todo item not found: \(id.uuidString)"
            case let .invalidDestinationIndex(index):
                return "Invalid destination index: \(index)"
            }
        }
    }

    private let store: TodoStore
    private let repository: TodoRepository
    private let now: () -> Date
    private let makeID: () -> UUID

    init(
        store: TodoStore,
        repository: TodoRepository,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.store = store
        self.repository = repository
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    func load() throws -> TodoRepositoryLoadResult {
        let result = try repository.load()
        store.replace(with: result.document, issue: result.recoveryIssue)
        return result
    }

    @discardableResult
    func createList(title: String) throws -> TodoList {
        let normalizedTitle = try validateTitle(title)
        let timestamp = now()

        return try applyMutation { document in
            let list = TodoList(
                id: makeID(),
                title: normalizedTitle,
                todos: [],
                createdAt: timestamp,
                updatedAt: timestamp
            )
            document.lists.append(list)
            document.updatedAt = timestamp
            return list
        }
    }

    @discardableResult
    func updateListTitle(listID: UUID, title: String) throws -> TodoList {
        let normalizedTitle = try validateTitle(title)
        let timestamp = now()

        return try applyMutation { document in
            let listIndex = try indexOfList(withID: listID, in: document)
            document.lists[listIndex].title = normalizedTitle
            document.lists[listIndex].updatedAt = timestamp
            document.updatedAt = timestamp
            return document.lists[listIndex]
        }
    }

    @discardableResult
    func createTodo(
        in listID: UUID,
        title: String,
        notes: String? = nil
    ) throws -> TodoItem {
        let normalizedTitle = try validateTitle(title)
        let normalizedNotes = normalizeNotes(notes)
        let timestamp = now()

        return try applyMutation { document in
            let listIndex = try indexOfList(withID: listID, in: document)
            let sortOrder = document.lists[listIndex].todos.count
            let todo = TodoItem(
                id: makeID(),
                title: normalizedTitle,
                notes: normalizedNotes,
                isCompleted: false,
                sortOrder: sortOrder,
                createdAt: timestamp,
                updatedAt: timestamp,
                completedAt: nil
            )
            document.lists[listIndex].todos.append(todo)
            document.lists[listIndex].updatedAt = timestamp
            document.updatedAt = timestamp
            return todo
        }
    }

    @discardableResult
    func updateTodo(
        in listID: UUID,
        todoID: UUID,
        request: TodoUpdateRequest
    ) throws -> TodoItem {
        let timestamp = now()

        return try applyMutation { document in
            let listIndex = try indexOfList(withID: listID, in: document)
            let todoIndex = try indexOfTodo(withID: todoID, in: document.lists[listIndex])

            if let title = request.title {
                document.lists[listIndex].todos[todoIndex].title = try validateTitle(title)
            }

            switch request.notes {
            case .preserve:
                break
            case let .set(notes):
                document.lists[listIndex].todos[todoIndex].notes = normalizeNotes(notes)
            case .clear:
                document.lists[listIndex].todos[todoIndex].notes = nil
            }

            document.lists[listIndex].todos[todoIndex].updatedAt = timestamp
            document.lists[listIndex].updatedAt = timestamp
            document.updatedAt = timestamp
            return document.lists[listIndex].todos[todoIndex]
        }
    }

    @discardableResult
    func completeTodo(
        in listID: UUID,
        todoID: UUID
    ) throws -> TodoItem {
        try setTodoCompletion(in: listID, todoID: todoID, isCompleted: true)
    }

    @discardableResult
    func setTodoCompletion(
        in listID: UUID,
        todoID: UUID,
        isCompleted: Bool
    ) throws -> TodoItem {
        let timestamp = now()

        return try applyMutation { document in
            let listIndex = try indexOfList(withID: listID, in: document)
            let todoIndex = try indexOfTodo(withID: todoID, in: document.lists[listIndex])

            document.lists[listIndex].todos[todoIndex].isCompleted = isCompleted
            document.lists[listIndex].todos[todoIndex].completedAt = isCompleted ? timestamp : nil
            document.lists[listIndex].todos[todoIndex].updatedAt = timestamp
            document.lists[listIndex].updatedAt = timestamp
            document.updatedAt = timestamp
            return document.lists[listIndex].todos[todoIndex]
        }
    }

    @discardableResult
    func moveTodo(
        in listID: UUID,
        todoID: UUID,
        to destinationIndex: Int
    ) throws -> TodoItem {
        let timestamp = now()

        return try applyMutation { document in
            let listIndex = try indexOfList(withID: listID, in: document)
            var list = document.lists[listIndex]
            let todoIndex = try indexOfTodo(withID: todoID, in: list)

            guard destinationIndex >= 0 && destinationIndex < list.todos.count else {
                throw CommandError.invalidDestinationIndex(destinationIndex)
            }

            let todo = list.todos.remove(at: todoIndex)
            list.todos.insert(todo, at: destinationIndex)
            list.todos = list.todos.enumerated().map { index, item in
                var updatedItem = item
                updatedItem.sortOrder = index
                updatedItem.updatedAt = timestamp
                return updatedItem
            }
            list.updatedAt = timestamp
            document.lists[listIndex] = list
            document.updatedAt = timestamp

            return list.todos[destinationIndex]
        }
    }

    private func applyMutation<T>(_ mutation: (inout TodoDocument) throws -> T) throws -> T {
        var workingDocument = store.document
        let result = try mutation(&workingDocument)
        try repository.save(workingDocument)
        store.replace(with: workingDocument)
        return result
    }

    private func validateTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CommandError.emptyTitle
        }
        return normalized
    }

    private func normalizeNotes(_ notes: String?) -> String? {
        guard let notes else {
            return nil
        }

        let normalized = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func indexOfList(withID listID: UUID, in document: TodoDocument) throws -> Int {
        guard let index = document.lists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.listNotFound(listID)
        }
        return index
    }

    private func indexOfTodo(withID todoID: UUID, in list: TodoList) throws -> Int {
        guard let index = list.todos.firstIndex(where: { $0.id == todoID }) else {
            throw CommandError.todoNotFound(todoID)
        }
        return index
    }
}
