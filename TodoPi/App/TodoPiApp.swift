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
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private lazy var repository = JSONTodoRepository()
    private lazy var commandService = TodoCommandService(store: store, repository: repository)

    private lazy var socketURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("todopi-\(UUID().uuidString).sock", isDirectory: false)
    private lazy var piWorkingDirectoryURL = PiLaunchConfiguration.defaultWorkingDirectoryURL()
    private lazy var piConfigDirectoryURL = PiLaunchConfiguration.defaultConfigDirectoryURL()
    private lazy var bridgeRuntimeInfoURL = PiLaunchConfiguration.defaultBridgeRuntimeInfoURL()
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
            workingDirectoryURL: piWorkingDirectoryURL,
            configDirectoryURL: piConfigDirectoryURL,
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
    private lazy var mainWindowViewModel = MainWindowViewModel(
        store: store,
        commandService: commandService,
        chatViewModel: chatViewModel
    )
    private lazy var mainWindowController = MainWindowController(viewModel: mainWindowViewModel)
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        preparePiRuntimeEnvironment()
        startBridgeIfNeeded()

        do {
            try commandService.load()
        } catch {
            NSLog("Failed to load todos: \(error.localizedDescription)")
        }

        menuBarController = MenuBarController { [weak mainWindowController] in
            mainWindowController?.showWindow()
        }

        guard !isRunningTests else {
            return
        }

        DispatchQueue.main.async { [weak mainWindowController] in
            mainWindowController?.showWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        piSessionManager.stop()
        bridgeServer.stop()
        removeBridgeRuntimeInfo()
    }

    private func preparePiRuntimeEnvironment() {
        do {
            try FileManager.default.createDirectory(at: piWorkingDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: piConfigDirectoryURL, withIntermediateDirectories: true)
        } catch {
            NSLog("Failed to create pi runtime directories: \(error.localizedDescription)")
            PiDebugLog.write("Failed to create pi runtime directories: \(error.localizedDescription)")
        }

        linkSharedPiAuthIfAvailable()
    }

    private func startBridgeIfNeeded() {
        do {
            try bridgeServer.start()
            publishBridgeRuntimeInfo()
        } catch {
            NSLog("Failed to start TodoPi bridge server: \(error.localizedDescription)")
            PiDebugLog.write("Failed to start TodoPi bridge server: \(error.localizedDescription)")
        }
    }

    private func publishBridgeRuntimeInfo() {
        do {
            let runtimeInfo = TodoPiBridgeRuntimeInfo(
                version: 1,
                socketPath: socketURL.path,
                token: bridgeToken,
                processIdentifier: Int32(ProcessInfo.processInfo.processIdentifier),
                updatedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(runtimeInfo)
            try FileManager.default.createDirectory(
                at: bridgeRuntimeInfoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: bridgeRuntimeInfoURL, options: .atomic)
            PiDebugLog.write("Published bridge runtime info to \(bridgeRuntimeInfoURL.path)")
        } catch {
            NSLog("Failed to publish TodoPi bridge runtime info: \(error.localizedDescription)")
            PiDebugLog.write("Failed to publish TodoPi bridge runtime info: \(error.localizedDescription)")
        }
    }

    private func removeBridgeRuntimeInfo() {
        do {
            if FileManager.default.fileExists(atPath: bridgeRuntimeInfoURL.path) {
                try FileManager.default.removeItem(at: bridgeRuntimeInfoURL)
                PiDebugLog.write("Removed bridge runtime info at \(bridgeRuntimeInfoURL.path)")
            }
        } catch {
            PiDebugLog.write("Failed to remove bridge runtime info: \(error.localizedDescription)")
        }
    }

    private func linkSharedPiAuthIfAvailable() {
        let fileManager = FileManager.default
        let sharedAuthURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
        let targetAuthURL = piConfigDirectoryURL.appendingPathComponent("auth.json", isDirectory: false)

        guard fileManager.fileExists(atPath: sharedAuthURL.path) else {
            PiDebugLog.write("Shared pi auth not found at \(sharedAuthURL.path)")
            return
        }

        do {
            try? fileManager.removeItem(at: targetAuthURL)
            try fileManager.createSymbolicLink(at: targetAuthURL, withDestinationURL: sharedAuthURL)
            PiDebugLog.write("Linked shared pi auth from \(sharedAuthURL.path) to \(targetAuthURL.path)")
        } catch {
            NSLog("Failed to link pi auth storage: \(error.localizedDescription)")
            PiDebugLog.write("Failed to link pi auth storage: \(error.localizedDescription)")
        }
    }
}
