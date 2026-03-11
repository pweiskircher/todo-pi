import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private let viewModel: MainWindowViewModel
    private(set) var window: NSWindow?

    init(viewModel: MainWindowViewModel) {
        self.viewModel = viewModel
    }

    @discardableResult
    func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let rootView = MainWindowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TodoPi"
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        self.window = window
        return window
    }

    func showWindow() {
        let window = makeWindowIfNeeded()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
