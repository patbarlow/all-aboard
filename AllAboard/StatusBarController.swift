import AppKit
import SwiftUI
import Sparkle

// Simple closure-based action target for menu buttons
private class MenuAction: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func invoke() { block() }
}

class StatusBarController: NSObject, NSWindowDelegate {
    private struct PinnedRow: Equatable {
        let tripId: String
        let departureTimePlanned: String
    }

    private var statusItem: NSStatusItem
    private var mainWindow: NSWindow?
    private let store: TripStore
    private let viewModel: MenuBarViewModel
    private let updaterController: SPUStandardUpdaterController
    private var pinnedRow: PinnedRow?
    private var pinCountdownTimer: Timer?
    private let liveTripCardController = LiveTripCardPanelController()
    private let selectionController = WindowSelectionController()
    /// Strong references to action handlers used in the current menu
    private var menuItemActions: [AnyObject] = []
    /// The currently displayed trips menu, kept for in-place rebuilds
    private var activeMenu: NSMenu?

    init(store: TripStore, viewModel: MenuBarViewModel, updaterController: SPUStandardUpdaterController) {
        self.store = store
        self.viewModel = viewModel
        self.updaterController = updaterController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "All Aboard")
            button.title = ""
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        updateStatusBarButtonTitle()
        startPinCountdownUpdates()

        NotificationCenter.default.addObserver(forName: .menuBarSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusBarButtonTitle()
        }
    }

    deinit {
        pinCountdownTimer?.invalidate()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        Task { @MainActor in await viewModel.refresh() }
        showTripsMenu()
    }

    // MARK: - Left Click: Trip Departures

    private func showTripsMenu() {
        let menu = NSMenu()
        syncPinnedRowWithLatestJourneys()
        buildTripsMenuContent(into: menu)
        activeMenu = menu

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildTripsMenuContent(into menu: NSMenu) {
        menu.removeAllItems()
        menuItemActions = []

        // Use store for trip names — reflects swaps immediately without waiting for a refresh
        let savedTrips = Array(store.savedTrips.prefix(3))

        if savedTrips.isEmpty {
            let item = NSMenuItem(title: "No saved trips", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if viewModel.tripsWithJourneys.isEmpty {
            let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (index, savedTrip) in savedTrips.enumerated() {
                if index > 0 { menu.addItem(.separator()) }

                let headerItem = NSMenuItem()
                let cleanName = savedTrip.name.replacingOccurrences(of: " Station", with: "")
                headerItem.view = makeHeaderRow(tripName: cleanName, tripId: savedTrip.id)
                menu.addItem(headerItem)

                if let tripData = viewModel.tripsWithJourneys.first(where: { $0.id == savedTrip.id }) {
                    if let error = tripData.error {
                        let item = NSMenuItem(title: "Error: \(error)", action: nil, keyEquivalent: "")
                        item.isEnabled = false
                        menu.addItem(item)
                    } else if tripData.journeys.isEmpty {
                        let item = NSMenuItem(title: "No upcoming trips", action: nil, keyEquivalent: "")
                        item.isEnabled = false
                        menu.addItem(item)
                    } else {
                        for journey in tripData.journeys {
                            menu.addItem(menuItem(for: journey, tripId: savedTrip.id))
                        }
                    }
                } else {
                    let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            }
        }

        // Footer
        menu.addItem(.separator())

        let openAction = MenuAction { [weak self] in
            self?.statusItem.menu?.cancelTracking()
            self?.statusItem.menu = nil
            self?.openApp()
        }
        menuItemActions.append(openAction)
        let openItem = NSMenuItem()
        openItem.view = makeTextMenuRow(title: "All Aboard", action: openAction)
        menu.addItem(openItem)

        let settingsAction = MenuAction { [weak self] in
            self?.openSettingsFromMenu()
        }
        menuItemActions.append(settingsAction)
        let settingsItem = NSMenuItem()
        settingsItem.view = makeTextMenuRow(title: "Settings", action: settingsAction)
        menu.addItem(settingsItem)

        let quitAction = MenuAction {
            NSApp.terminate(nil)
        }
        menuItemActions.append(quitAction)
        let quitItem = NSMenuItem()
        quitItem.view = makeTextMenuRow(title: "Quit All Aboard Completely", action: quitAction)
        menu.addItem(quitItem)
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
        }
        item.isEnabled = true
        return item
    }

    private func presentMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = MainWindowView(store: store, selectionController: selectionController) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.refresh()
                self.updateStatusBarButtonTitle()
            }
        }
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = AppColors.sidebarBackgroundNS
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.delegate = self
        window.setContentSize(NSSize(width: 760, height: 520))

        mainWindow = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        self.statusItem.menu = nil
        DispatchQueue.main.async { [weak self] in
            self?.presentMainWindow()
        }
    }

    private func openSettingsFromMenu() {
        statusItem.menu?.cancelTracking()
        statusItem.menu = nil
        openSettings()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        self.statusItem.menu = nil
        DispatchQueue.main.async { [weak self] in
            self?.presentMainWindow()
            self?.selectionController.showSettings = true
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == mainWindow {
            mainWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePinnedRow(tripId: String, departureTimePlanned: String) {
        let selectedRow = PinnedRow(tripId: tripId, departureTimePlanned: departureTimePlanned)
        if pinnedRow == selectedRow {
            unpinAndCloseCard()
        } else {
            pinnedRow = selectedRow
            updateStatusBarButtonTitle()
            showLiveCard()
        }
        statusItem.menu?.cancelTracking()
        statusItem.menu = nil
    }

    private func showLiveCard() {
        guard let snapshot = liveTripCardSnapshot() else { return }
        liveTripCardController.show(snapshot: snapshot) { [weak self] in
            // User closed via X — unpin too
            self?.pinnedRow = nil
            self?.updateStatusBarButtonTitle()
        }
    }

    private func unpinAndCloseCard() {
        pinnedRow = nil
        updateStatusBarButtonTitle()
        liveTripCardController.close()
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

        // Find the first FUTURE departure from the first saved trip
        guard let firstTrip = viewModel.tripsWithJourneys.first else {
            button.title = ""
            return
        }

        // Skip past departures — find the next one that hasn't left yet
        let now = Date()
        let nextJourney = firstTrip.journeys.first { journey in
            guard let leg = journey.legs.first else { return false }
            let timeStr = leg.origin.departureTimeEstimated ?? leg.origin.departureTimePlanned
            guard let departDate = TimeFormatting.parseTime(timeStr) else { return false }
            // Keep if departure is in the future or within 60s past (still "Due")
            return departDate.timeIntervalSince(now) > -60
        }

        guard let journey = nextJourney, let firstLeg = journey.legs.first else {
            button.title = ""
            return
        }

        // Use estimated time if available, fall back to planned
        let departureTime = firstLeg.origin.departureTimeEstimated ?? firstLeg.origin.departureTimePlanned

        var parts: [String] = []

        if AppSettings.showDepartureTimeInMenuBar {
            let timeStr = TimeFormatting.formatTime(departureTime)
            if !timeStr.isEmpty { parts.append(timeStr) }
        }

        if AppSettings.showCountdownInMenuBar {
            let countdown = TimeFormatting.formatTimeUntil(departureTime)
            if !countdown.isEmpty { parts.append(countdown) }
        }

        if parts.isEmpty {
            button.title = ""
        } else {
            button.title = " \(parts.joined(separator: " \u{00b7} "))"
        }
    }

    private func startPinCountdownUpdates() {
        pinCountdownTimer?.invalidate()
        pinCountdownTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.handlePinTimerTick()
        }
    }

    private func handlePinTimerTick() {
        updateStatusBarButtonTitle()

        guard let pinnedRow else { return }

        // Auto-close and unpin 60s after scheduled departure
        if let departDate = TimeFormatting.parseTime(pinnedRow.departureTimePlanned),
           Date().timeIntervalSince(departDate) > 60 {
            unpinAndCloseCard()
            return
        }

        // Keep the card snapshot fresh if it’s visible
        if liveTripCardController.isVisible, let snapshot = liveTripCardSnapshot() {
            liveTripCardController.update(snapshot: snapshot)
        }
    }

    private func liveTripCardSnapshot() -> LiveTripCardSnapshot? {
        guard let pinnedRow else { return nil }
        guard let trip = viewModel.tripsWithJourneys.first(where: { $0.id == pinnedRow.tripId }),
              let journey = trip.journeys.first(where: {
                  $0.legs.first?.origin.departureTimePlanned == pinnedRow.departureTimePlanned
              }) else {
            return nil
        }

        let firstLeg = journey.legs.first
        let transportLeg = journey.legs.first { $0.transportation != nil }

        let plannedISO = transportLeg?.origin.departureTimePlanned ?? firstLeg?.origin.departureTimePlanned
        let departTime = TimeFormatting.formatTime(plannedISO)

        // Clean stop name: strip ", Platform X, City" suffix and " Station" suffix
        let rawStop = transportLeg?.origin.name ?? firstLeg?.origin.name ?? trip.origin.name
        let currentStop = (rawStop.components(separatedBy: ",").first ?? rawStop)
            .replacingOccurrences(of: " Station", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Route: use trip name but clean up " Station"
        let route = trip.name.replacingOccurrences(of: " Station", with: "")

        let platformRaw = transportLeg?.origin.properties?.platformName
            ?? transportLeg?.origin.properties?.platform ?? ""
        let platformText = platformRaw.isEmpty ? "" :
            (platformRaw.lowercased().hasPrefix("platform") ? platformRaw : "Platform \(platformRaw)")

        var statusText = ""
        if let planned = TimeFormatting.parseTime(transportLeg?.origin.departureTimePlanned ?? firstLeg?.origin.departureTimePlanned),
           let estimated = TimeFormatting.parseTime(transportLeg?.origin.departureTimeEstimated ?? firstLeg?.origin.departureTimeEstimated) {
            let diffMins = Int(round(estimated.timeIntervalSince(planned) / 60))
            statusText = diffMins <= 0 ? "On time" : "\(diffMins) min\(diffMins == 1 ? "" : "s") late"
        }

        return LiveTripCardSnapshot(
            route: route,
            departureISOTime: plannedISO,
            departureDisplay: departTime,
            statusText: statusText,
            platformText: platformText,
            currentStop: currentStop
        )
    }

    // MARK: - Menu Header with Swap Button

    private func makeTextMenuRow(title: String, action: MenuAction) -> NSView {
        class HoverTextRow: NSView {
            private var tracking: NSTrackingArea?
            var isHovered = false { didSet { needsDisplay = true } }
            var onSelect: (() -> Void)?

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                if let tracking { removeTrackingArea(tracking) }
                tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
                addTrackingArea(tracking!)
            }
            override func mouseEntered(with event: NSEvent) { isHovered = true }
            override func mouseExited(with event: NSEvent) { isHovered = false }
            override func mouseDown(with event: NSEvent) { onSelect?() }
            override func draw(_ dirtyRect: NSRect) {
                super.draw(dirtyRect)
                if isHovered {
                    let insetRect = bounds.insetBy(dx: 6, dy: 2)
                    let path = NSBezierPath(roundedRect: insetRect, xRadius: 6, yRadius: 6)
                    NSColor.labelColor.withAlphaComponent(0.06).setFill()
                    path.fill()
                }
            }
        }

        let container = HoverTextRow()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onSelect = { action.invoke() }

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 28),
            container.widthAnchor.constraint(equalToConstant: 340),
        ])

        return container
    }

    private func makeHeaderRow(tripName: String, tripId: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let hPad: CGFloat = 12

        let titleField = NSTextField(labelWithString: tripName)
        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .secondaryLabelColor
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingMiddle

        container.addSubview(titleField)

        let swapIcon = NSImage(systemSymbolName: "arrow.left.arrow.right",
                               accessibilityDescription: "Swap direction")!
        let swapBtn = NSButton(image: swapIcon, target: nil, action: nil)
        swapBtn.bezelStyle = .regularSquare
        swapBtn.isBordered = false
        swapBtn.translatesAutoresizingMaskIntoConstraints = false
        swapBtn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        swapBtn.contentTintColor = .tertiaryLabelColor

        let action = MenuAction { [weak self] in
            guard let self, let menu = self.activeMenu else { return }
            self.store.reverseTrip(id: tripId)
            self.buildTripsMenuContent(into: menu)
            Task { @MainActor in
                await self.viewModel.refresh()
                guard let menu = self.activeMenu else { return }
                self.buildTripsMenuContent(into: menu)
            }
        }
        menuItemActions.append(action)
        swapBtn.target = action
        swapBtn.action = #selector(MenuAction.invoke)

        container.addSubview(swapBtn)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),
            titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: swapBtn.leadingAnchor, constant: -6),

            swapBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),
            swapBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            swapBtn.widthAnchor.constraint(equalToConstant: 20),
            swapBtn.heightAnchor.constraint(equalToConstant: 20),

            container.heightAnchor.constraint(equalToConstant: 28),
            container.widthAnchor.constraint(equalToConstant: 340)
        ])

        return container
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

