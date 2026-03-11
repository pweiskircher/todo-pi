import Combine
import Foundation

@MainActor
final class MainWindowViewModel: ObservableObject {
    let store: TodoStore
    let chatViewModel: ChatViewModel

    @Published private(set) var selectedListID: UUID?
    @Published private(set) var selectedTodoID: UUID?
    @Published var listTitleDraft = ""
    @Published var todoBodyDraft = ""
    @Published private(set) var editorErrorDescription: String?

    private let commandService: TodoCommandService
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: TodoStore,
        commandService: TodoCommandService,
        chatViewModel: ChatViewModel
    ) {
        self.store = store
        self.commandService = commandService
        self.chatViewModel = chatViewModel
        self.selectedListID = store.document.lists.first?.id
        self.selectedTodoID = store.document.lists.first?.todos.first?.id
        syncEditorDrafts()

        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        store.$document
            .map(\.lists)
            .sink { [weak self] lists in
                self?.syncSelection(with: lists)
                self?.syncEditorDrafts()
            }
            .store(in: &cancellables)
    }

    var lists: [TodoList] {
        store.document.lists
    }

    var selectedList: TodoList? {
        guard let selectedListID else {
            return nil
        }
        return lists.first(where: { $0.id == selectedListID })
    }

    var selectedTodo: TodoItem? {
        guard let selectedTodoID else {
            return nil
        }
        return selectedList?.todos.first(where: { $0.id == selectedTodoID })
    }

    var loadIssueDescription: String? {
        store.lastLoadIssue?.errorDescription
    }

    func selectList(id: UUID?) {
        guard let id else {
            selectedListID = nil
            selectedTodoID = nil
            syncEditorDrafts()
            return
        }

        guard let list = lists.first(where: { $0.id == id }) else {
            return
        }

        selectedListID = id
        selectedTodoID = list.todos.first?.id
        editorErrorDescription = nil
        syncEditorDrafts()
    }

    func selectTodo(id: UUID?) {
        guard let id else {
            selectedTodoID = nil
            syncEditorDrafts()
            return
        }

        guard selectedList?.todos.contains(where: { $0.id == id }) == true else {
            return
        }

        selectedTodoID = id
        editorErrorDescription = nil
        syncEditorDrafts()
    }

    func createList() {
        do {
            let list = try commandService.createList(title: uniqueTitle(base: "New List", in: lists.map(\.title)))
            selectedListID = list.id
            selectedTodoID = nil
            editorErrorDescription = nil
            syncEditorDrafts()
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func deleteList(id: UUID) {
        do {
            try commandService.deleteList(listID: id)
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func createTodo() {
        guard let list = selectedList else {
            return
        }

        do {
            let todo = try commandService.createTodo(
                in: list.id,
                title: uniqueTitle(base: "New Todo", in: list.todos.map(\.title))
            )
            selectedTodoID = todo.id
            editorErrorDescription = nil
            syncEditorDrafts()
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func deleteTodo(id: UUID) {
        guard let list = selectedList else {
            return
        }

        do {
            try commandService.deleteTodo(in: list.id, todoID: id)
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func saveListTitle() {
        guard let list = selectedList else {
            return
        }

        renameList(id: list.id, title: listTitleDraft)
    }

    func renameList(id: UUID, title: String) {
        do {
            _ = try commandService.updateListTitle(listID: id, title: title)
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func saveTodoBody() {
        guard let list = selectedList, let todo = selectedTodo else {
            return
        }

        do {
            let request = parseTodoBody(todoBodyDraft)
            _ = try commandService.updateTodo(in: list.id, todoID: todo.id, request: request)
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func renameTodoTitle(id: UUID, title: String) {
        guard let list = selectedList else {
            return
        }

        do {
            _ = try commandService.updateTodo(
                in: list.id,
                todoID: id,
                request: TodoUpdateRequest(title: title, notes: .preserve)
            )
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func discardTodoEdits() {
        editorErrorDescription = nil
        syncEditorDrafts()
    }

    func toggleCompletion(for todoID: UUID) {
        guard let list = selectedList,
              let todo = list.todos.first(where: { $0.id == todoID }) else {
            return
        }

        do {
            _ = try commandService.setTodoCompletion(in: list.id, todoID: todoID, isCompleted: !todo.isCompleted)
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    func moveTodos(fromOffsets: IndexSet, toOffset: Int) {
        guard let list = selectedList else {
            return
        }

        var desiredIDs = sortedTodos(in: list).map(\.id)
        desiredIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        do {
            for targetIndex in desiredIDs.indices {
                guard let currentList = selectedList else { break }
                let currentIDs = sortedTodos(in: currentList).map(\.id)
                let desiredID = desiredIDs[targetIndex]
                if currentIDs[targetIndex] != desiredID {
                    _ = try commandService.moveTodo(in: list.id, todoID: desiredID, to: targetIndex)
                }
            }
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
    }

    private func syncSelection(with lists: [TodoList]) {
        if let selectedListID,
           let selectedList = lists.first(where: { $0.id == selectedListID }) {
            syncTodoSelection(with: selectedList)
            return
        }

        self.selectedListID = lists.first?.id
        syncTodoSelection(with: lists.first)
    }

    private func syncTodoSelection(with list: TodoList?) {
        guard let list else {
            selectedTodoID = nil
            return
        }

        if let selectedTodoID,
           list.todos.contains(where: { $0.id == selectedTodoID }) {
            return
        }

        self.selectedTodoID = list.todos.first?.id
    }

    private func syncEditorDrafts() {
        listTitleDraft = selectedList?.title ?? ""
        todoBodyDraft = selectedTodo.map(Self.todoBodyText(from:)) ?? ""
    }

    private func parseTodoBody(_ body: String) -> TodoUpdateRequest {
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n")
        let title: String
        let notesText: String

        if let newlineRange = normalizedBody.range(of: "\n") {
            title = String(normalizedBody[..<newlineRange.lowerBound])
            notesText = String(normalizedBody[newlineRange.upperBound...])
        } else {
            title = normalizedBody
            notesText = ""
        }

        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TodoUpdateRequest(
            title: title,
            notes: trimmedNotes.isEmpty ? .clear : .set(notesText)
        )
    }

    private func uniqueTitle(base: String, in existingTitles: [String]) -> String {
        if !existingTitles.contains(base) {
            return base
        }

        var index = 2
        while existingTitles.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func sortedTodos(in list: TodoList) -> [TodoItem] {
        list.todos.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private static func todoBodyText(from todo: TodoItem) -> String {
        guard let notes = todo.notes, !notes.isEmpty else {
            return todo.title
        }
        return "\(todo.title)\n\n\(notes)"
    }
}
