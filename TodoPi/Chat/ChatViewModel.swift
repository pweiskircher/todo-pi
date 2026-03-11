import Combine
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
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
        case starting
        case ready
        case busy
        case failed(String)
    }

    @Published var draftMessage = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var status: Status = .offline

    private let sessionManager: PiSessionManaging?
    private let now: () -> Date
    private let makeID: () -> UUID
    private var activeAssistantMessageID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    init(
        sessionManager: PiSessionManaging? = nil,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.sessionManager = sessionManager
        self.now = now
        self.makeID = makeID

        sessionManager?.statePublisher
            .sink { [weak self] state in
                self?.status = Self.mapStatus(from: state)
            }
            .store(in: &cancellables)

        sessionManager?.eventPublisher
            .sink { [weak self] event in
                self?.handleSessionEvent(event)
            }
            .store(in: &cancellables)
    }

    func sendDraft() {
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }

        appendMessage(role: .user, text: message)
        draftMessage = ""

        guard let sessionManager else {
            appendMessage(role: .system, text: "pi integration is not connected yet.")
            return
        }

        Task {
            do {
                try await sessionManager.sendPrompt(message)
            } catch {
                activeAssistantMessageID = nil
                appendMessage(role: .system, text: error.localizedDescription)
            }
        }
    }

    private func handleSessionEvent(_ event: PiSessionEvent) {
        switch event {
        case let .assistantMessageChanged(text):
            upsertAssistantMessage(text: text, isComplete: false)
        case let .assistantMessageCompleted(text):
            upsertAssistantMessage(text: text, isComplete: true)
        case let .systemNotice(text):
            activeAssistantMessageID = nil
            appendMessage(role: .system, text: text)
        }
    }

    private func upsertAssistantMessage(text: String, isComplete: Bool) {
        guard !text.isEmpty else {
            return
        }

        if let activeAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == activeAssistantMessageID }) {
            messages[index] = ChatMessage(
                id: activeAssistantMessageID,
                role: .assistant,
                text: text,
                createdAt: messages[index].createdAt
            )
        } else {
            let messageID = makeID()
            messages.append(
                ChatMessage(
                    id: messageID,
                    role: .assistant,
                    text: text,
                    createdAt: now()
                )
            )
            activeAssistantMessageID = messageID
        }

        if isComplete {
            activeAssistantMessageID = nil
        }
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

    private static func mapStatus(from state: PiSessionManager.State) -> Status {
        switch state {
        case .idle, .stopped:
            return .offline
        case .starting:
            return .starting
        case .ready:
            return .ready
        case .busy:
            return .busy
        case let .failed(message):
            return .failed(message)
        }
    }
}
