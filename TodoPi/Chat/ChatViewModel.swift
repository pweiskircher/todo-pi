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
        case starting
        case ready
        case busy
        case failed(String)
    }

    @Published var draftMessage = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var status: Status = .offline

    private let sessionManager: PiSessionManager?
    private let now: () -> Date
    private let makeID: () -> UUID
    private var cancellables: Set<AnyCancellable> = []

    init(
        sessionManager: PiSessionManager? = nil,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.sessionManager = sessionManager
        self.now = now
        self.makeID = makeID

        sessionManager?.$state
            .sink { [weak self] state in
                self?.status = Self.mapStatus(from: state)
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
                try await sessionManager.startIfNeeded()
                appendMessage(role: .system, text: "pi is connected. Prompt delivery comes in the next phase.")
            } catch {
                appendMessage(role: .system, text: error.localizedDescription)
            }
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
