import Combine
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var document: TodoDocument
    @Published private(set) var lastLoadIssue: TodoRepositoryRecoveryIssue?

    init(
        document: TodoDocument = .empty(),
        lastLoadIssue: TodoRepositoryRecoveryIssue? = nil
    ) {
        self.document = document
        self.lastLoadIssue = lastLoadIssue
    }

    func replace(
        with document: TodoDocument,
        issue: TodoRepositoryRecoveryIssue? = nil
    ) {
        self.document = document
        self.lastLoadIssue = issue
    }
}
