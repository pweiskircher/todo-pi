import XCTest
@testable import TodoPi

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testMakeWindowIfNeededReusesTheSameWindow() {
        let controller = MainWindowController()

        let firstWindow = controller.makeWindowIfNeeded()
        let secondWindow = controller.makeWindowIfNeeded()

        XCTAssertTrue(firstWindow === secondWindow)
        XCTAssertEqual(firstWindow.title, "TodoPi")
    }
}
