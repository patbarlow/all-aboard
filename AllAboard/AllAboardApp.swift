import SwiftUI
import Sparkle

@main
struct AllAboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(store: store, viewModel: viewModel)
        viewModel.startAutoRefreshIfNeeded()
    }
}
