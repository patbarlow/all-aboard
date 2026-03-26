import SwiftUI
import Sparkle

enum ReleaseChannel: String {
    case stable
    case beta
}

enum AppSettings {
    static let releaseChannelKey = "release-channel"
    static let enableBetaFeaturesKey = "enable-beta-features"
    static let enableLiveCardKey = "enable-live-card"
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

    static var enableLiveCard: Bool {
        get { UserDefaults.standard.bool(forKey: enableLiveCardKey) }
        set { UserDefaults.standard.set(newValue, forKey: enableLiveCardKey) }
    }
}

final class UpdateFeedDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        switch AppSettings.releaseChannel {
        case .stable: return AppSettings.stableFeedURL
        case .beta: return AppSettings.betaFeedURL
        }
    }
}

@main
struct AllAboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            statusBarController = StatusBarController(store: store, viewModel: viewModel, updaterController: updaterController)
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
