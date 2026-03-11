import Combine
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
        case system
        case thinking
        case tool
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
    private var activeMessageIDsByKey: [String: UUID] = [:]
    private var lastCompletedMessageTextByKey: [String: String] = [:]
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
        lastCompletedMessageTextByKey.removeAll()

        guard let sessionManager else {
            appendMessage(role: .system, text: "pi integration is not connected yet.")
            return
        }

        Task {
            do {
                try await sessionManager.sendPrompt(message)
            } catch {
                clearActiveMessage(key: "assistant")
                appendMessage(role: .system, text: error.localizedDescription)
            }
        }
    }

    private func handleSessionEvent(_ event: PiSessionEvent) {
        switch event {
        case let .assistantMessageChanged(text):
            upsertMessage(key: "assistant", role: .assistant, text: text, isComplete: false)
        case let .assistantMessageCompleted(text):
            upsertMessage(key: "assistant", role: .assistant, text: text, isComplete: true)
        case let .thinkingChanged(text):
            upsertMessage(key: "thinking", role: .thinking, text: text, isComplete: false)
        case let .thinkingCompleted(text):
            upsertMessage(key: "thinking", role: .thinking, text: text, isComplete: true)
        case let .toolCallChanged(key, text):
            upsertMessage(key: "toolcall:\(key)", role: .tool, text: text, isComplete: false)
        case let .toolCallCompleted(key, text, _):
            upsertMessage(key: "toolcall:\(key)", role: .tool, text: text, isComplete: true)
        case let .toolExecutionChanged(key, text):
            upsertMessage(key: "toolexec:\(key)", role: .tool, text: text, isComplete: false)
        case let .toolExecutionCompleted(key, text, _):
            upsertMessage(key: "toolexec:\(key)", role: .tool, text: text, isComplete: true)
        case let .systemNotice(text):
            appendMessage(role: .system, text: text)
        }
    }

    private func upsertMessage(key: String, role: ChatMessage.Role, text: String, isComplete: Bool) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        if !isComplete {
            lastCompletedMessageTextByKey.removeValue(forKey: key)
        } else if activeMessageIDsByKey[key] == nil,
                  lastCompletedMessageTextByKey[key] == trimmedText {
            return
        }

        if let messageID = activeMessageIDsByKey[key],
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index] = ChatMessage(
                id: messageID,
                role: role,
                text: trimmedText,
                createdAt: messages[index].createdAt
            )
        } else {
            let messageID = makeID()
            messages.append(
                ChatMessage(
                    id: messageID,
                    role: role,
                    text: trimmedText,
                    createdAt: now()
                )
            )
            activeMessageIDsByKey[key] = messageID
        }

        if isComplete {
            lastCompletedMessageTextByKey[key] = trimmedText
            clearActiveMessage(key: key)
        }
    }

    private func clearActiveMessage(key: String) {
        activeMessageIDsByKey.removeValue(forKey: key)
    }

    private func appendMessage(role: ChatMessage.Role, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        messages.append(
            ChatMessage(
                id: makeID(),
                role: role,
                text: trimmedText,
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
