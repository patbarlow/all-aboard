import AppKit
import SwiftUI
import Sparkle

class StatusBarController: NSObject, NSWindowDelegate {
    private struct PinnedRow: Equatable {
        let tripId: String
        let departureTimePlanned: String
    }

    private var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private let store: TripStore
    private let viewModel: MenuBarViewModel
    private var pinnedRow: PinnedRow?
    private var pinCountdownTimer: Timer?

    init(store: TripStore, viewModel: MenuBarViewModel) {
        self.store = store
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "All Aboard")
            button.title = " All Aboard"
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusBarButtonTitle()
        startPinCountdownUpdates()
    }

    deinit {
        pinCountdownTimer?.invalidate()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            Task { @MainActor in await viewModel.refresh() }
            showTripsMenu()
        }
    }

    // MARK: - Left Click: Trip Departures

    private func showTripsMenu() {
        let menu = NSMenu()
        let trips = viewModel.tripsWithJourneys

        syncPinnedRowWithLatestJourneys()

        if trips.isEmpty && store.savedTrips.isEmpty {
            let item = NSMenuItem(title: "Right-click to add a trip", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if trips.isEmpty {
            let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (index, trip) in trips.enumerated() {
                if index > 0 { menu.addItem(.separator()) }

                do {
                    let headerItem = NSMenuItem()
                    let headerView = NSView()
                    headerView.translatesAutoresizingMaskIntoConstraints = false

                    let hPad: CGFloat = 12
                    let vPad: CGFloat = 6

                    let titleField = NSTextField(labelWithString: trip.name)
                    titleField.font = .systemFont(ofSize: 12, weight: .semibold)
                    titleField.textColor = .secondaryLabelColor
                    titleField.translatesAutoresizingMaskIntoConstraints = false

                    headerView.addSubview(titleField)

                    NSLayoutConstraint.activate([
                        titleField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: hPad),
                        titleField.topAnchor.constraint(equalTo: headerView.topAnchor, constant: vPad),
                        titleField.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -hPad),
                        titleField.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -vPad),
                        headerView.widthAnchor.constraint(equalToConstant: 340)
                    ])

                    headerItem.view = headerView
                    menu.addItem(headerItem)
                }

                if let error = trip.error {
                    let item = NSMenuItem(title: "Error: \(error)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                } else if trip.journeys.isEmpty {
                    let item = NSMenuItem(title: "No upcoming trips", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                } else {
                    for journey in trip.journeys {
                        menu.addItem(menuItem(for: journey, tripId: trip.id))
                    }
                }
            }
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(for journey: Journey, tripId: String) -> NSMenuItem {
        let firstLeg = journey.legs.first
        let lastLeg = journey.legs.last
        let transportLeg = journey.legs.first { $0.transportation != nil }
        let departureTimePlanned = firstLeg?.origin.departureTimePlanned ?? ""

        let timeUntil = TimeFormatting.formatTimeUntil(firstLeg?.origin.departureTimePlanned)
        let departTime = TimeFormatting.formatTime(firstLeg?.origin.departureTimePlanned)
        let arriveTime = TimeFormatting.formatTime(lastLeg?.destination.arrivalTimePlanned)

        // Journey duration from departure to arrival
        var durationText = ""
        if let departDate = TimeFormatting.parseTime(firstLeg?.origin.departureTimePlanned),
           let arriveDate = TimeFormatting.parseTime(lastLeg?.destination.arrivalTimePlanned) {
            let seconds = Int(arriveDate.timeIntervalSince(departDate))
            if seconds > 0 { durationText = TimeFormatting.formatDuration(seconds) }
        }

        // Platform from the first transport leg's departure stop
        let rawPlatform = transportLeg?.origin.properties?.platformName
            ?? transportLeg?.origin.properties?.platform
        var subtitle = durationText
        if let raw = rawPlatform, !raw.isEmpty {
            let platformText = raw.lowercased().hasPrefix("platform") ? raw : "Platform \(raw)"
            subtitle = durationText.isEmpty ? platformText : "\(durationText) · \(platformText)"
        }

        // Realtime status from planned vs estimated departure
        var realtimeStatus = ""
        let originLoc = transportLeg?.origin ?? firstLeg?.origin
        if let planned = TimeFormatting.parseTime(originLoc?.departureTimePlanned),
           let estimated = TimeFormatting.parseTime(originLoc?.departureTimeEstimated) {
            let diffMins = Int(round(estimated.timeIntervalSince(planned) / 60))
            if diffMins <= 0 {
                realtimeStatus = "On time"
            } else {
                realtimeStatus = "\(diffMins) min\(diffMins == 1 ? "" : "s") late"
            }
        }

        let item = NSMenuItem()
        let isPinned = pinnedRow == PinnedRow(
            tripId: tripId,
            departureTimePlanned: departureTimePlanned
        )
        item.view = makeMenuRow(
            depart: departTime,
            arrive: arriveTime,
            timeUntil: timeUntil,
            subtitle: subtitle,
            realtimeStatus: realtimeStatus,
            isPinned: isPinned
        ) { [weak self] in
            self?.togglePinnedRow(
                tripId: tripId,
                departureTimePlanned: departureTimePlanned
            )
        )
        item.isEnabled = true
        return item
    }

    private func presentSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Host the TripCreationView so users can add/remove saved trips
        let rootView = TripCreationView(store: store) { [weak self] in
            guard let self else { return }
            // Refresh the menubar trips after changes
            Task { @MainActor in
                await self.viewModel.refresh()
            }
        }
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "All Aboard"
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Right Click: Settings Menu

    private func showContextMenu() {
        let menu = NSMenu()

        // Settings
        let settingsItem = NSMenuItem(title: "Manage Trips…", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        // Refresh Now
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit All Aboard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        // Present the menu from the status item
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() {
        Task { @MainActor in
            await viewModel.refresh()
        }
    }

    @objc private func showSettings() {
        // Activate app and close the status menu so the window can appear
        NSApp.activate(ignoringOtherApps: true)
        self.statusItem.menu = nil

        // Present our lightweight SwiftUI settings window
        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }

    @objc private func checkForUpdates() {
        SUUpdater.shared()?.checkForUpdates(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePinnedRow(tripId: String, departureTimePlanned: String) {
        let selectedRow = PinnedRow(
            tripId: tripId,
            departureTimePlanned: departureTimePlanned
        )
        if pinnedRow == selectedRow {
            pinnedRow = nil
        } else {
            pinnedRow = selectedRow
        }

        updateStatusBarButtonTitle()
        statusItem.menu?.cancelTracking()
        statusItem.menu = nil
    }

    private func syncPinnedRowWithLatestJourneys() {
        guard let pinnedRow else {
            updateStatusBarButtonTitle()
            return
        }

        let stillExists = viewModel.tripsWithJourneys.contains { trip in
            trip.id == pinnedRow.tripId
                && trip.journeys.contains { journey in
                    journey.legs.first?.origin.departureTimePlanned == pinnedRow.departureTimePlanned
                }
        }

        if !stillExists {
            self.pinnedRow = nil
        }

        updateStatusBarButtonTitle()
    }

    private func updateStatusBarButtonTitle() {
        guard let button = statusItem.button else { return }

        let baseTitle = " All Aboard"
        guard let pinnedRow else {
            button.title = baseTitle
            return
        }

        let pinnedJourney = viewModel.tripsWithJourneys
            .first(where: { $0.id == pinnedRow.tripId })?
            .journeys
            .first(where: { $0.legs.first?.origin.departureTimePlanned == pinnedRow.departureTimePlanned })

        let minutesUntil = TimeFormatting.formatTimeUntil(pinnedJourney?.legs.first?.origin.departureTimePlanned)
        if minutesUntil.isEmpty {
            button.title = baseTitle
        } else {
            button.title = "\(baseTitle)  \(minutesUntil)"
        }
    }

    private func startPinCountdownUpdates() {
        pinCountdownTimer?.invalidate()
        pinCountdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateStatusBarButtonTitle()
        }
    }

    // MARK: - Menu Row View

    private func makeMenuRow(
        depart: String,
        arrive: String,
        timeUntil: String,
        subtitle: String,
        realtimeStatus: String,
        isPinned: Bool,
        onSelect: @escaping () -> Void
    ) -> NSView {
        class HoverRowView: NSView {
            private var tracking: NSTrackingArea?
            var isHovered: Bool = false { didSet { needsDisplay = true } }
            var isPinned: Bool = false { didSet { needsDisplay = true } }
            var onSelect: (() -> Void)?

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                if let tracking { removeTrackingArea(tracking) }
                let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
                tracking = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
                addTrackingArea(tracking!)
            }
            override func mouseEntered(with event: NSEvent) { isHovered = true }
            override func mouseExited(with event: NSEvent) { isHovered = false }
            override func mouseDown(with event: NSEvent) {
                onSelect?()
            }
            override func draw(_ dirtyRect: NSRect) {
                super.draw(dirtyRect)
                // Draw a standard-looking hover highlight: inset, rounded, and using system background
                if isHovered || isPinned {
                    let insetRect = bounds.insetBy(dx: 6, dy: 3)
                    let path = NSBezierPath(roundedRect: insetRect, xRadius: 6, yRadius: 6)
                    let alpha: CGFloat = isPinned ? 0.14 : 0.06
                    NSColor.labelColor.withAlphaComponent(alpha).setFill()
                    path.fill()
                }
            }
        }

        let container = HoverRowView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isPinned = isPinned
        container.onSelect = onSelect

        let hPad: CGFloat = 12
        let vPad: CGFloat = 6

        // Line 1: "depart → arrive" (left) | timeUntil (right)
        let timesLabel = NSTextField(labelWithString: "\(depart) → \(arrive)")
        timesLabel.tag = 1
        timesLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        timesLabel.textColor = .labelColor
        timesLabel.alignment = .left
        timesLabel.translatesAutoresizingMaskIntoConstraints = false

        let untilLabel = NSTextField(labelWithString: timeUntil)
        untilLabel.tag = 99
        untilLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        untilLabel.alignment = .right
        untilLabel.translatesAutoresizingMaskIntoConstraints = false

        untilLabel.textColor = isPinned ? .controlAccentColor : .labelColor

        // Line 2 left: duration · platform
        let serviceLabel = NSTextField(labelWithString: subtitle)
        serviceLabel.font = .systemFont(ofSize: 11)
        serviceLabel.textColor = .secondaryLabelColor
        serviceLabel.alignment = .left
        serviceLabel.translatesAutoresizingMaskIntoConstraints = false

        // Line 2 right: realtime status
        let statusLabel = NSTextField(labelWithString: realtimeStatus)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        if realtimeStatus.hasSuffix("late") {
            statusLabel.textColor = .systemRed
        } else {
            statusLabel.textColor = .secondaryLabelColor
        }

        container.addSubview(timesLabel)
        container.addSubview(untilLabel)
        container.addSubview(serviceLabel)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Line 1
            timesLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),
            timesLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: vPad),

            untilLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),
            untilLabel.firstBaselineAnchor.constraint(equalTo: timesLabel.firstBaselineAnchor),
            untilLabel.leadingAnchor.constraint(greaterThanOrEqualTo: timesLabel.trailingAnchor, constant: 8),

            // Line 2
            serviceLabel.leadingAnchor.constraint(equalTo: timesLabel.leadingAnchor),
            serviceLabel.topAnchor.constraint(equalTo: timesLabel.bottomAnchor, constant: 2),
            serviceLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vPad),

            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),
            statusLabel.firstBaselineAnchor.constraint(equalTo: serviceLabel.firstBaselineAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: serviceLabel.trailingAnchor, constant: 8),

            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 2 * vPad + 16 + 14),

            // Width for menu row
            container.widthAnchor.constraint(equalToConstant: 340)
        ])

        return container
    }
}
