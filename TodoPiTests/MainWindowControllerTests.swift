import XCTest
@testable import TodoPi

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testMakeWindowIfNeededReusesTheSameWindow() {
        let controller = MainWindowController(viewModel: makeViewModel())

        let firstWindow = controller.makeWindowIfNeeded()
        let secondWindow = controller.makeWindowIfNeeded()

        XCTAssertTrue(firstWindow === secondWindow)
        XCTAssertEqual(firstWindow.title, "TodoPi")
    }

    private func makeViewModel() -> MainWindowViewModel {
        let store = TodoStore(document: .empty())
        let chatViewModel = ChatViewModel()
        return MainWindowViewModel(store: store, chatViewModel: chatViewModel)
    }
}
