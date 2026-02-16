import AppKit
import SwiftUI
import Sparkle

class StatusBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private let store: TripStore
    private let viewModel: MenuBarViewModel

    init(store: TripStore, viewModel: MenuBarViewModel) {
        self.store = store
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "All Aboard")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            showTripsMenu()
        }
    }

    // MARK: - Left Click: Trip Departures

    private func showTripsMenu() {
        let menu = NSMenu()
        let trips = viewModel.tripsWithJourneys

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
                        menu.addItem(menuItem(for: journey))
                    }
                }
            }
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func cleanedServiceText(from raw: String) -> String {
        let prefixes = [
            "Sydney Trains",
            "Sydney Metro",
            "NSW TrainLink",
            "Sydney Light Rail",
            "Sydney Buses",
            "Sydney Ferries"
        ]
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in prefixes {
            if text.hasPrefix(p) {
                text = text.dropFirst(p.count).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if text.hasPrefix("Network ") {
            text = String(text.dropFirst("Network ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Collapse extra spaces and remove leading punctuation like '-' or ':' if present
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-:\u{2013}\u{2014} "))
        return text
    }

    private func menuItem(for journey: Journey) -> NSMenuItem {
        let firstLeg = journey.legs.first
        let lastLeg = journey.legs.last
        let transportLeg = journey.legs.first { $0.transportation != nil }

        let timeUntil = TimeFormatting.formatTimeUntil(firstLeg?.origin.departureTimePlanned)
        let departTime = TimeFormatting.formatTime(firstLeg?.origin.departureTimePlanned)
        let arriveTime = TimeFormatting.formatTime(lastLeg?.destination.arrivalTimePlanned)
        let lineName = transportLeg?.transportation?.disassembledName ?? ""
        let serviceCode: String = transportLeg?.transportation?.name ?? lineName

        let item = NSMenuItem()
        item.view = makeMenuRow(
            depart: departTime,
            arrive: arriveTime,
            timeUntil: timeUntil,
            serviceText: cleanedServiceText(from: serviceCode)
        )
        item.target = self
        item.action = #selector(noop)
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

    @objc private func noop() {
        // Intentionally empty: enables menu items without performing an action
    }

    // MARK: - Menu Row View

    private func makeMenuRow(
        depart: String,
        arrive: String,
        timeUntil: String,
        serviceText: String
    ) -> NSView {
        class HoverRowView: NSView {
            private var tracking: NSTrackingArea?
            var isHovered: Bool = false { didSet { needsDisplay = true } }
            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                if let tracking { removeTrackingArea(tracking) }
                let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
                tracking = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
                addTrackingArea(tracking!)
            }
            override func mouseEntered(with event: NSEvent) { isHovered = true }
            override func mouseExited(with event: NSEvent) { isHovered = false }
            override func draw(_ dirtyRect: NSRect) {
                super.draw(dirtyRect)
                // Draw a standard-looking hover highlight: inset, rounded, and using system background
                if isHovered {
                    let insetRect = bounds.insetBy(dx: 6, dy: 3)
                    let path = NSBezierPath(roundedRect: insetRect, xRadius: 6, yRadius: 6)
                    // Use subtle, low-opacity system fill for hover highlight
                    NSColor.labelColor.withAlphaComponent(0.06).setFill()
                    path.fill()
                }
            }
        }

        let container = HoverRowView()
        container.translatesAutoresizingMaskIntoConstraints = false

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

        // Color thresholds for timeUntil
        let normalized = timeUntil.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized == "due" || normalized == "1 min" || normalized == "1min" || normalized == "0 min" || normalized == "0min" {
            untilLabel.textColor = .systemRed
        } else if let minutes = Int(normalized.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()), minutes <= 2 {
            // 2 or 3? Requirement says 3 mins orange; make <=2 red covered above, <=3 orange
            untilLabel.textColor = .systemOrange
        } else if normalized.hasSuffix("min") || normalized.hasSuffix("mins") {
            if let minutes = Int(normalized.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()), minutes <= 3 {
                untilLabel.textColor = .systemOrange
            } else {
                untilLabel.textColor = .secondaryLabelColor
            }
        } else {
            untilLabel.textColor = .secondaryLabelColor
        }

        // Line 2: service text (smaller, left)
        let serviceLabel = NSTextField(labelWithString: serviceText)
        serviceLabel.font = .systemFont(ofSize: 11)
        serviceLabel.textColor = .secondaryLabelColor
        serviceLabel.alignment = .left
        serviceLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(timesLabel)
        container.addSubview(untilLabel)
        container.addSubview(serviceLabel)

        NSLayoutConstraint.activate([
            // Line 1
            timesLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hPad),
            timesLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: vPad),

            untilLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hPad),
            untilLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            untilLabel.leadingAnchor.constraint(greaterThanOrEqualTo: timesLabel.trailingAnchor, constant: 8),

            // Line 2
            serviceLabel.leadingAnchor.constraint(equalTo: timesLabel.leadingAnchor),
            serviceLabel.topAnchor.constraint(equalTo: timesLabel.bottomAnchor, constant: 2),
            serviceLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -hPad),
            serviceLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vPad),

            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 2 * vPad + 16 + 14),

            // Width for menu row
            container.widthAnchor.constraint(equalToConstant: 340)
        ])

        return container
    }
}

