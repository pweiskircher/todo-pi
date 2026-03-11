import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private(set) var window: NSWindow?

    @discardableResult
    func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let rootView = MainWindowView()
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "TodoPi"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.minSize = NSSize(width: 720, height: 480)
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
