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
    private lazy var repository = JSONTodoRepository()
    private lazy var commandService = TodoCommandService(store: store, repository: repository)

    private lazy var socketURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("todopi-\(UUID().uuidString).sock", isDirectory: false)
    private lazy var bridgeToken = UUID().uuidString
    private lazy var bridgeServer = PiBridgeServer(
        socketURL: socketURL,
        authToken: bridgeToken,
        store: store,
        commandService: commandService
    )
    // TODO(Settings): Add a user-configurable pi executable path override.
    // Finder-launched apps do not reliably inherit the same PATH as Terminal,
    // so long-term we should let users point TodoPi at their preferred pi binary.
    private lazy var launchConfiguration = PiLaunchConfiguration.defaultExtensionURL().map {
        PiLaunchConfiguration(
            workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            extensionURL: $0,
            socketURL: socketURL,
            authToken: bridgeToken
        )
    }
    private lazy var piSessionManager = PiSessionManager(
        launchConfiguration: launchConfiguration,
        bridgeServer: bridgeServer
    )
    private lazy var chatViewModel = ChatViewModel(sessionManager: piSessionManager)
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

    func applicationWillTerminate(_ notification: Notification) {
        piSessionManager.stop()
    }
}
