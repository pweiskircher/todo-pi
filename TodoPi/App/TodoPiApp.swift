import AppKit
import SwiftUI

@main
struct TodoPiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TodoStore()
    private let chatViewModel = ChatViewModel()
    private lazy var repository = JSONTodoRepository()
    private lazy var commandService = TodoCommandService(store: store, repository: repository)
    private lazy var mainWindowViewModel = MainWindowViewModel(store: store, chatViewModel: chatViewModel)
    private lazy var mainWindowController = MainWindowController(viewModel: mainWindowViewModel)
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try commandService.load()
        } catch {
            NSLog("Failed to load todos: \(error.localizedDescription)")
        }

        menuBarController = MenuBarController { [weak mainWindowController] in
            mainWindowController?.showWindow()
        }
    }
}
