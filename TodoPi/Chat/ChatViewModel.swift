import Combine
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case system
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
}

@MainActor
final class ChatViewModel: ObservableObject {
    enum Status: Equatable {
        case offline
    }

    @Published var draftMessage = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var status: Status = .offline

    private let now: () -> Date
    private let makeID: () -> UUID

    init(
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.now = now
        self.makeID = makeID
    }

    func sendDraft() {
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }

        appendMessage(role: .user, text: message)
        appendMessage(role: .system, text: "pi integration is not connected yet.")
        draftMessage = ""
    }

    private func appendMessage(role: ChatMessage.Role, text: String) {
        messages.append(
            ChatMessage(
                id: makeID(),
                role: role,
                text: text,
                createdAt: now()
            )
        )
    }
}
