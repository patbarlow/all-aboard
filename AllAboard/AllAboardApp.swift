import SwiftUI
import Sparkle

extension Notification.Name {
    static let menuBarSettingsChanged = Notification.Name("menuBarSettingsChanged")
    static let modalVisibilityChanged = Notification.Name("modalVisibilityChanged")
}

enum AppSettings {
    static let showDepartureTimeKey = "show-departure-time-menu-bar"
    static let showCountdownKey = "show-countdown-menu-bar"
    static let feedURL = "https://raw.githubusercontent.com/patbarlow/all-aboard/main/appcast.xml"

    static var showDepartureTimeInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: showDepartureTimeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: showDepartureTimeKey)
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
        }
    }

    static var showCountdownInMenuBar: Bool {
        get {
            if UserDefaults.standard.object(forKey: showCountdownKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showCountdownKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showCountdownKey)
            NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
        }
    }
}

final class UpdateFeedDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        AppSettings.feedURL
    }
}

@main
struct AllAboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible scenes — app UI is managed by StatusBarController
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TripStore()
    lazy var viewModel = MenuBarViewModel(store: store)
    private var statusBarController: StatusBarController?
    private var activationWindow: NSWindow?

    private let updateFeedDelegate = UpdateFeedDelegate()
    let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updateFeedDelegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        if AuthManager.shared.isSignedIn {
            Task { await startApp() }
        } else {
            showSignInWindow()
        }
    }

    @objc private func appDidBecomeActive() {
        guard statusBarController != nil else { return }
        Task { await refreshSessionOrSignOut() }
    }

    // Refreshes the session. Only shows the sign-in window if the session is
    // actually invalid (401) — subscription lapse is handled within the app UI.
    private func refreshSessionOrSignOut() async {
        let user = await AuthManager.shared.refresh()
        if user == nil && !AuthManager.shared.isSignedIn {
            await MainActor.run {
                statusBarController = nil
                showSignInWindow()
            }
        }
    }

    private func startApp() async {
        await AuthManager.shared.refresh()
        await MainActor.run { launchApp() }
    }

    func launchApp() {
        activationWindow?.close()
        activationWindow = nil
        if statusBarController == nil {
            statusBarController = StatusBarController(store: store, viewModel: viewModel, updaterController: updaterController)
            viewModel.startAutoRefreshIfNeeded()
        }
    }

    private func showSignInWindow() {
        let view = SignInView { [weak self] in
            self?.launchApp()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: hosting.fittingSize.height)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "All Aboard"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        activationWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
