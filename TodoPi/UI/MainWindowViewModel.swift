import Combine
import Foundation

@MainActor
final class MainWindowViewModel: ObservableObject {
    let store: TodoStore
    let chatViewModel: ChatViewModel

    @Published private(set) var currentDocument: TodoDocument
    @Published private(set) var currentLoadIssue: TodoRepositoryRecoveryIssue?
    @Published private(set) var selectedListID: UUID?
    @Published private(set) var selectedTodoID: UUID?
    @Published var listTitleDraft = ""
    @Published var todoBodyDraft = ""
    @Published private(set) var editorErrorDescription: String?

    private let commandService: TodoCommandService
    private var cancellables: Set<AnyCancellable> = []
    private var isSyncingDrafts = false
    private var isListTitleDirty = false
    private var isTodoBodyDirty = false
    private var lastDraftedListID: UUID?
    private var lastDraftedTodoID: UUID?
    private var listTitleDraftBaseUpdatedAt: Date?
    private var todoBodyDraftBaseUpdatedAt: Date?

    init(
        store: TodoStore,
        commandService: TodoCommandService,
        chatViewModel: ChatViewModel
    ) {
        self.store = store
        self.commandService = commandService
        self.chatViewModel = chatViewModel
        self.currentDocument = store.document
        self.currentLoadIssue = store.lastLoadIssue
        self.selectedListID = store.document.lists.first?.id
        self.selectedTodoID = nil
        syncEditorDrafts(with: lists)

        store.$document
            .sink { [weak self] document in
                guard let self else {
                    return
                }
                self.currentDocument = document
                self.syncSelection(with: document.lists)
                self.syncEditorDrafts(with: document.lists)
            }
            .store(in: &cancellables)

        store.$lastLoadIssue
            .sink { [weak self] issue in
                self?.currentLoadIssue = issue
            }
            .store(in: &cancellables)

        $listTitleDraft
            .dropFirst()
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] _ in
                guard let self, !self.isSyncingDrafts else {
                    return
                }
                self.isListTitleDirty = true
            })
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.autosaveListTitleIfNeeded()
            }
            .store(in: &cancellables)

        $todoBodyDraft
            .dropFirst()
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] _ in
                guard let self, !self.isSyncingDrafts else {
                    return
                }
                self.isTodoBodyDirty = true
            })
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.autosaveTodoBodyIfNeeded()
            }
            .store(in: &cancellables)
    }

    var lists: [TodoList] {
        currentDocument.lists
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
        currentLoadIssue?.errorDescription
    }

    func selectList(id: UUID?) {
        if id == nil, !lists.isEmpty {
            return
        }

        persistDraftsIfNeeded()

        guard let id else {
            selectedListID = nil
            selectedTodoID = nil
            syncEditorDrafts(with: lists)
            return
        }

        guard lists.contains(where: { $0.id == id }) else {
            return
        }

        selectedListID = id
        selectedTodoID = nil
        editorErrorDescription = nil
        syncEditorDrafts(with: lists)
    }

    func selectTodo(id: UUID?) {
        persistDraftsIfNeeded()

        guard let id else {
            selectedTodoID = nil
            syncEditorDrafts(with: lists)
            return
        }

        guard selectedList?.todos.contains(where: { $0.id == id }) == true else {
            return
        }

        selectedTodoID = id
        editorErrorDescription = nil
        syncEditorDrafts(with: lists)
    }

    func createList() {
        persistDraftsIfNeeded()

        do {
            let list = try commandService.createList(title: uniqueTitle(base: "New List", in: lists.map(\.title)))
            selectedListID = list.id
            selectedTodoID = nil
            editorErrorDescription = nil
            syncEditorDrafts(with: lists)
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
        persistDraftsIfNeeded()

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
            syncEditorDrafts(with: lists)
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

        if isListTitleDirty,
           let baseUpdatedAt = listTitleDraftBaseUpdatedAt,
           list.updatedAt != baseUpdatedAt {
            editorErrorDescription = "This list changed while you were editing. Your draft was not saved."
            return
        }

        let normalizedDraft = listTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDraft.isEmpty else {
            return
        }

        guard normalizedDraft != list.title else {
            isListTitleDirty = false
            listTitleDraftBaseUpdatedAt = list.updatedAt
            return
        }

        do {
            let updatedList = try commandService.updateListTitle(listID: list.id, title: listTitleDraft)
            listTitleDraft = updatedList.title
            listTitleDraftBaseUpdatedAt = updatedList.updatedAt
            isListTitleDirty = false
            editorErrorDescription = nil
        } catch {
            editorErrorDescription = error.localizedDescription
        }
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

        if isTodoBodyDirty,
           let baseUpdatedAt = todoBodyDraftBaseUpdatedAt,
           todo.updatedAt != baseUpdatedAt {
            editorErrorDescription = "This todo changed while you were editing. Your draft was not saved."
            return
        }

        let normalizedDraft = todoBodyDraft.replacingOccurrences(of: "\r\n", with: "\n")
        let currentBody = Self.todoBodyText(from: todo).replacingOccurrences(of: "\r\n", with: "\n")
        guard normalizedDraft != currentBody else {
            isTodoBodyDirty = false
            todoBodyDraftBaseUpdatedAt = todo.updatedAt
            return
        }

        do {
            let request = parseTodoBody(todoBodyDraft)
            let updatedTodo = try commandService.updateTodo(in: list.id, todoID: todo.id, request: request)
            todoBodyDraft = Self.todoBodyText(from: updatedTodo)
            todoBodyDraftBaseUpdatedAt = updatedTodo.updatedAt
            isTodoBodyDirty = false
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

    func persistDraftsIfNeeded() {
        saveListTitle()
        saveTodoBody()
    }

    func discardTodoEdits() {
        editorErrorDescription = nil
        syncEditorDrafts(with: lists)
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

        self.selectedTodoID = nil
    }

    private func selectedList(in lists: [TodoList]) -> TodoList? {
        guard let selectedListID else {
            return nil
        }
        return lists.first(where: { $0.id == selectedListID })
    }

    private func selectedTodo(in lists: [TodoList]) -> TodoItem? {
        guard let selectedTodoID,
              let selectedList = selectedList(in: lists) else {
            return nil
        }
        return selectedList.todos.first(where: { $0.id == selectedTodoID })
    }

    private func syncEditorDrafts(with lists: [TodoList]) {
        isSyncingDrafts = true
        defer { isSyncingDrafts = false }

        if let selectedList = selectedList(in: lists) {
            if lastDraftedListID != selectedList.id || !isListTitleDirty {
                listTitleDraft = selectedList.title
                listTitleDraftBaseUpdatedAt = selectedList.updatedAt
                isListTitleDirty = false
                lastDraftedListID = selectedList.id
            }
        } else {
            listTitleDraft = ""
            listTitleDraftBaseUpdatedAt = nil
            isListTitleDirty = false
            lastDraftedListID = nil
        }

        if let selectedTodo = selectedTodo(in: lists) {
            let bodyText = Self.todoBodyText(from: selectedTodo)
            if lastDraftedTodoID != selectedTodo.id || !isTodoBodyDirty {
                todoBodyDraft = bodyText
                todoBodyDraftBaseUpdatedAt = selectedTodo.updatedAt
                isTodoBodyDirty = false
                lastDraftedTodoID = selectedTodo.id
            }
        } else {
            todoBodyDraft = ""
            todoBodyDraftBaseUpdatedAt = nil
            isTodoBodyDirty = false
            lastDraftedTodoID = nil
        }
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

    private func autosaveListTitleIfNeeded() {
        guard !isSyncingDrafts else {
            return
        }
        saveListTitle()
    }

    private func autosaveTodoBodyIfNeeded() {
        guard !isSyncingDrafts else {
            return
        }
        saveTodoBody()
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
