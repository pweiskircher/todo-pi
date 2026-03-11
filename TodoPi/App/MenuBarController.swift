import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onActivate: () -> Void
    private let menu = NSMenu()

    init(onActivate: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onActivate = onActivate
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TodoPi")
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleButtonAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Open TodoPi"
    }

    private func configureMenu() {
        menu.addItem(NSMenuItem(title: "Open TodoPi", action: #selector(openFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TodoPi", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
    }

    @objc private func handleButtonAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onActivate()
            return
        }

        switch event.type {
        case .rightMouseUp:
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        default:
            onActivate()
        }
    }

    @objc private func openFromMenu() {
        onActivate()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}
