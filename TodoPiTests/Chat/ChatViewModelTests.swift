import Combine
import XCTest
@testable import TodoPi

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testSendDraftAppendsUserAndSystemMessagesAndClearsDraft() {
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        let ids = IDSequence([
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        ])
        let viewModel = ChatViewModel(
            now: { timestamp },
            makeID: { ids.next() }
        )
        viewModel.draftMessage = "Help me organize today"

        viewModel.sendDraft()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].text, "Help me organize today")
        XCTAssertEqual(viewModel.messages[1].role, .system)
        XCTAssertEqual(viewModel.messages[1].text, "pi integration is not connected yet.")
        XCTAssertEqual(viewModel.draftMessage, "")
    }

    func testSendDraftIgnoresWhitespaceOnlyInput() {
        let viewModel = ChatViewModel()
        viewModel.draftMessage = "   \n  "

        viewModel.sendDraft()

        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testSendDraftStreamsAssistantResponseFromSessionManager() async {
        let timestamp = Date(timeIntervalSince1970: 1_731_000_000)
        let ids = IDSequence([
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        ])
        let sessionManager = FakePiSessionManager()
        sessionManager.sendPromptHandler = { _, events in
            events.send(.assistantMessageChanged("Hello"))
            events.send(.assistantMessageChanged("Hello world"))
            events.send(.assistantMessageCompleted("Hello world"))
        }
        let viewModel = ChatViewModel(
            sessionManager: sessionManager,
            now: { timestamp },
            makeID: { ids.next() }
        )
        viewModel.draftMessage = "hi"

        viewModel.sendDraft()
        await settleTasks()

        XCTAssertEqual(sessionManager.promptedMessages, ["hi"])
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].text, "hi")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertEqual(viewModel.messages[1].text, "Hello world")
    }

    func testThinkingAndToolEventsAppearInTranscript() {
        let sessionManager = FakePiSessionManager()
        let viewModel = ChatViewModel(sessionManager: sessionManager)

        sessionManager.events.send(.thinkingChanged("Plan step 1"))
        sessionManager.events.send(.thinkingCompleted("Plan step 1\nPlan step 2"))
        sessionManager.events.send(.toolCallChanged(key: "createTodo", text: "tool call: createTodo"))
        sessionManager.events.send(.toolExecutionChanged(key: "call-1", text: "running tool: createTodo"))
        sessionManager.events.send(.toolExecutionCompleted(key: "call-1", text: "finished tool: createTodo", isError: false))

        XCTAssertEqual(viewModel.messages.count, 3)
        XCTAssertEqual(viewModel.messages[0].role, .thinking)
        XCTAssertEqual(viewModel.messages[0].text, "Plan step 1\nPlan step 2")
        XCTAssertEqual(viewModel.messages[1].role, .tool)
        XCTAssertEqual(viewModel.messages[1].text, "tool call: createTodo")
        XCTAssertEqual(viewModel.messages[2].role, .tool)
        XCTAssertEqual(viewModel.messages[2].text, "finished tool: createTodo")
    }

    func testSendDraftAppendsSystemErrorWhenPromptFails() async {
        let sessionManager = FakePiSessionManager()
        sessionManager.sendPromptError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "prompt failed"])
        let viewModel = ChatViewModel(sessionManager: sessionManager)
        viewModel.draftMessage = "hi"

        viewModel.sendDraft()
        await settleTasks()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[1].role, .system)
        XCTAssertEqual(viewModel.messages[1].text, "prompt failed")
    }

    func testSessionSystemNoticeAppendsSystemMessage() {
        let sessionManager = FakePiSessionManager()
        let viewModel = ChatViewModel(sessionManager: sessionManager)

        sessionManager.events.send(.systemNotice("bridge disconnected"))

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].role, .system)
        XCTAssertEqual(viewModel.messages[0].text, "bridge disconnected")
    }

    private func settleTasks() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }
}

@MainActor
private final class FakePiSessionManager: PiSessionManaging {
    let states = CurrentValueSubject<PiSessionManager.State, Never>(.idle)
    let events = PassthroughSubject<PiSessionEvent, Never>()

    var promptedMessages: [String] = []
    var sendPromptError: Error?
    var sendPromptHandler: ((String, PassthroughSubject<PiSessionEvent, Never>) -> Void)?

    var statePublisher: AnyPublisher<PiSessionManager.State, Never> {
        states.eraseToAnyPublisher()
    }

    var eventPublisher: AnyPublisher<PiSessionEvent, Never> {
        events.eraseToAnyPublisher()
    }

    func startIfNeeded() async throws {
        states.send(.ready)
    }

    func sendPrompt(_ message: String) async throws {
        promptedMessages.append(message)
        states.send(.busy)

        if let sendPromptError {
            states.send(.failed(sendPromptError.localizedDescription))
            throw sendPromptError
        }

        sendPromptHandler?(message, events)
        states.send(.ready)
    }
}

private final class IDSequence {
    private var ids: [UUID]

    init(_ ids: [UUID]) {
        self.ids = ids
    }

    func next() -> UUID {
        ids.removeFirst()
    }
}
