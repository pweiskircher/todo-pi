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
