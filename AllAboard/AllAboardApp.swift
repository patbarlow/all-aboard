import SwiftUI
import Sparkle

enum ReleaseChannel: String {
    case stable
    case beta
}

enum AppSettings {
    static let releaseChannelKey = "release-channel"
    static let enableBetaFeaturesKey = "enable-beta-features"
    static let stableFeedURL = "https://raw.githubusercontent.com/patbarlow/all-aboard/main/appcast.xml"
    static let betaFeedURL = "https://raw.githubusercontent.com/patbarlow/all-aboard/main/appcast-beta.xml"

    static var releaseChannel: ReleaseChannel {
        get {
            guard let raw = UserDefaults.standard.string(forKey: releaseChannelKey),
                  let channel = ReleaseChannel(rawValue: raw) else {
                return .stable
            }
            return channel
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: releaseChannelKey)
        }
    }

    static var enableBetaFeatures: Bool {
        get { UserDefaults.standard.bool(forKey: enableBetaFeaturesKey) }
        set { UserDefaults.standard.set(newValue, forKey: enableBetaFeaturesKey) }
    }
}

@main
struct AllAboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        let feedURL: String
        switch AppSettings.releaseChannel {
        case .stable:
            feedURL = AppSettings.stableFeedURL
        case .beta:
            feedURL = AppSettings.betaFeedURL
        }
        UserDefaults.standard.set(feedURL, forKey: "SUFeedURL")
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        Settings {
            TripCreationView(
                store: appDelegate.store,
                onTripsChanged: {
                    Task { await appDelegate.viewModel.refresh() }
                }
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TripStore()
    lazy var viewModel = MenuBarViewModel(store: store)
    private var statusBarController: StatusBarController?
    private var activationWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LicenseManager.shared.isActivated {
            Task { await startAppIfLicenseValid() }
        } else {
            showActivationWindow()
        }
    }

    private func startAppIfLicenseValid() async {
        let valid = await LicenseManager.shared.validate()
        await MainActor.run {
            if valid {
                launchApp()
            } else {
                showActivationWindow()
            }
        }
    }

    func launchApp() {
        activationWindow?.close()
        activationWindow = nil
        if statusBarController == nil {
            statusBarController = StatusBarController(store: store, viewModel: viewModel)
            viewModel.startAutoRefreshIfNeeded()
        }
    }

    private func showActivationWindow() {
        let view = LicenseActivationView { [weak self] in
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
