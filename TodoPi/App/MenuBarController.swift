import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onActivate: () -> Void

    init(onActivate: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onActivate = onActivate
        super.init()
        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TodoPi")
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick)
        button.toolTip = "Open TodoPi"
    }

    @objc private func handleClick() {
        onActivate()
    }
}
