import SwiftUI
import Sparkle
import AppKit

// Visual radius constants for consistent rounding
struct UIRadius {
    static let parentCard: CGFloat = 8    // large containers (main content, settings sheet)
    static let sheetContainer: CGFloat = 8 // outer settings sheet container
    static let sheetInset: CGFloat = 8      // sheet content padding from edges
    static let sheetCard: CGFloat = 8      // inner card inside settings sheet
    static let innerTile: CGFloat = 8     // smaller tiles inside cards (license key, input rows)
    static let keycap: CGFloat = 8        // tiny keycap-like elements
}

// Reusable card styling for content surfaces
struct AppCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(AppColors.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppColors.contentBorder, lineWidth: 1)
            )
    }
}

extension View {
    func appCard(cornerRadius: CGFloat) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Sidebar Navigation

enum SidebarDestination: Hashable {
    case trip(String)
}

@Observable
class WindowSelectionController {
    var pendingSelection: SidebarDestination?
    var showSettings = false
}

// MARK: - Main Window

struct MainWindowView: View {
    var store: TripStore
    var selectionController: WindowSelectionController
    var updaterController: SPUStandardUpdaterController
    var onTripsChanged: (() -> Void)?

    @State private var selection: SidebarDestination?
    @State private var tripCreationVM: TripCreationViewModel
    @State private var journeys: [Journey] = []
    @State private var isLoadingJourneys = false
    @State private var journeyError: String?
    @State private var lastUpdated: Date?
    @State private var showingAddTrip = false
    @State private var showingSettings = false
    @State private var journeyCache: [String: [Journey]] = [:]
    @State private var fetchTask: Task<Void, Never>?
    @State private var isLoadingEarlier = false
    @State private var isLoadingLater = false
    @State private var canLoadEarlier = true
    @State private var canLoadLater = true

    // Drag reorder state
    @State private var draggingTripId: String?
    @State private var dragTranslation: CGFloat = 0

    private let rowHeight: CGFloat = 36 // 32pt button + 4pt spacing

    /// Live preview of the sidebar order while dragging — computed from the real
    /// saved order plus the in-progress drag, without mutating the store until drop.
    private var displayedTrips: [SavedTrip] {
        guard let draggingTripId,
              let fromIndex = store.savedTrips.firstIndex(where: { $0.id == draggingTripId }) else {
            return store.savedTrips
        }
        var trips = store.savedTrips
        let dragged = trips.remove(at: fromIndex)
        let offsetSlots = Int((dragTranslation / rowHeight).rounded())
        let targetIndex = max(0, min(trips.count, fromIndex + offsetSlots))
        trips.insert(dragged, at: targetIndex)
        return trips
    }

    /// The sub-row-height pixel remainder, so the dragged card tracks the cursor smoothly
    /// between the row-height increments that trigger a reflow of the other rows.
    private var residualOffset: CGFloat {
        let slot = (dragTranslation / rowHeight).rounded()
        return dragTranslation - slot * rowHeight
    }

    init(store: TripStore, selectionController: WindowSelectionController, updaterController: SPUStandardUpdaterController, onTripsChanged: (() -> Void)? = nil) {
        self.store = store
        self.selectionController = selectionController
        self.updaterController = updaterController
        self.onTripsChanged = onTripsChanged
        self._tripCreationVM = State(initialValue: TripCreationViewModel(store: store))
    }

    private var selectedTrip: SavedTrip? {
        guard case .trip(let id) = selection else { return nil }
        return store.savedTrips.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .padding(.top, 8)
        }
        .background(AppColors.sidebarBackground)
        .frame(width: 760, height: 520)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { selectPreviousTrip(); return .handled }
        .onKeyPress(.downArrow) { selectNextTrip(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "n")) { _ in showingAddTrip = true; return .handled }
        .onAppear {
            if let pending = selectionController.pendingSelection {
                selection = pending
                selectionController.pendingSelection = nil
            } else if selection == nil, let first = store.savedTrips.first {
                selection = .trip(first.id)
            }
            if selectionController.showSettings {
                showingSettings = true
                selectionController.showSettings = false
            }
        }
        .onChange(of: selectionController.pendingSelection) { _, newVal in
            if let newVal {
                selection = newVal
                selectionController.pendingSelection = nil
            }
        }
        .onChange(of: selectionController.showSettings) { _, newVal in
            if newVal {
                showingSettings = true
                selectionController.showSettings = false
            }
        }
        .onChange(of: selection) { _, newVal in
            if case .trip = newVal {
                beginFetch()
            }
        }
        .overlay {
            if showingSettings || showingAddTrip {
                ZStack {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingSettings = false
                            showingAddTrip = false
                        }

                    Group {
                        if showingSettings {
                            SettingsSheet(updaterController: updaterController, onDismiss: { showingSettings = false })
                                .frame(width: 520, height: 380)
                                .clipShape(RoundedRectangle(cornerRadius: UIRadius.parentCard))
                        } else if showingAddTrip {
                            AddTripSheet(store: store, viewModel: tripCreationVM, onTripsChanged: onTripsChanged) { tripId in
                                if let tripId { selection = .trip(tripId) }
                                showingAddTrip = false
                            }
                            .frame(width: 460, height: 480)
                            .appCard(cornerRadius: UIRadius.parentCard)
                        }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
                }
                .zIndex(1000)
                .transition(.opacity)
            }
        }
        .onChange(of: showingSettings || showingAddTrip) { _, isShowing in
            NotificationCenter.default.post(name: .modalVisibilityChanged, object: isShowing)
        }
    }

    // MARK: - Trip Navigation

    private func selectPreviousTrip() {
        guard let current = selection, case .trip(let id) = current,
              let idx = store.savedTrips.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        selection = .trip(store.savedTrips[idx - 1].id)
    }

    private func selectNextTrip() {
        guard let current = selection, case .trip(let id) = current,
              let idx = store.savedTrips.firstIndex(where: { $0.id == id }),
              idx < store.savedTrips.count - 1 else { return }
        selection = .trip(store.savedTrips[idx + 1].id)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                SidebarHeading("Saved Trips")
                    .padding(.leading, 10)
                Spacer()
                AppButton(systemImage: "plus", variant: .subtle) {
                    tripCreationVM.reset()
                    showingAddTrip = true
                }
                .help("Add Trip")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 6)

            // Trip list with drag reorder
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(displayedTrips.enumerated()), id: \.element.id) { index, trip in
                        let isDragging = draggingTripId == trip.id

                        if index == 1 || index == 3 {
                            Divider().padding(.vertical, 2)
                        }

                        AppButton(
                            "\(displayName(trip.origin.name)) \u{2192} \(displayName(trip.destination.name))",
                            variant: .subtle,
                            isActive: selection == .trip(trip.id),
                            fullWidth: true
                        ) {
                            selection = .trip(trip.id)
                        }
                        .opacity(isDragging ? 0.9 : 1)
                        .scaleEffect(isDragging ? 1.03 : 1)
                        .zIndex(isDragging ? 1 : 0)
                        .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: 8, y: 3)
                        .offset(y: isDragging ? residualOffset : 0)
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    if draggingTripId == nil {
                                        draggingTripId = trip.id
                                        dragTranslation = 0
                                    }
                                    let newTranslation = value.translation.height
                                    let oldSlot = (dragTranslation / rowHeight).rounded()
                                    let newSlot = (newTranslation / rowHeight).rounded()
                                    if oldSlot != newSlot {
                                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.78)) {
                                            dragTranslation = newTranslation
                                        }
                                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                    } else {
                                        dragTranslation = newTranslation
                                    }
                                }
                                .onEnded { _ in
                                    let finalOrder = displayedTrips
                                    draggingTripId = nil
                                    dragTranslation = 0
                                    if finalOrder.map(\.id) != store.savedTrips.map(\.id) {
                                        store.savedTrips = finalOrder
                                        store.persistOrder()
                                        onTripsChanged?()
                                    }
                                }
                        )
                        .contextMenu {
                            Button {
                                store.reverseTrip(id: trip.id)
                                onTripsChanged?()
                                if case .trip(trip.id) = selection { beginFetch() }
                            } label: {
                                Label("Swap Direction", systemImage: "arrow.left.arrow.right")
                            }
                            Button {
                                store.duplicateTrip(id: trip.id)
                                onTripsChanged?()
                            } label: {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) {
                                store.removeTrip(id: trip.id)
                                onTripsChanged?()
                                if case .trip(trip.id) = selection {
                                    selection = store.savedTrips.first.map { .trip($0.id) }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Spacer()

            // Settings
            HStack {
                AppButton(systemImage: "gearshape", variant: .subtle) {
                    showingSettings = true
                }
                .help("Settings")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let trip = selectedTrip {
            TripDetailView(
                trip: trip,
                journeys: journeys,
                isLoading: isLoadingJourneys,
                errorMessage: journeyError,
                canLoadEarlier: canLoadEarlier,
                canLoadLater: canLoadLater,
                isLoadingEarlier: isLoadingEarlier,
                isLoadingLater: isLoadingLater,
                onSwap: {
                    store.reverseTrip(id: trip.id)
                    onTripsChanged?()
                    beginFetch()
                },
                onRefresh: {
                    beginFetch()
                },
                onLoadEarlier: { loadEarlier() },
                onLoadLater: { loadLater() }
            )
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tram.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.tertiaryText)
            Text("No trip selected")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
            Text("Add a trip to see departure times")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.tertiaryText)

            AppButton("Add Trip", systemImage: "plus", variant: .primary) {
                tripCreationVM.reset()
                showingAddTrip = true
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appCard(cornerRadius: UIRadius.parentCard)
    }

    // MARK: - Data

    /// A stable-ish dedupe key for a journey (Journey.id is a fresh UUID on every decode).
    private func journeyKey(_ journey: Journey) -> String {
        journey.legs.first?.origin.departureTimePlanned ?? UUID().uuidString
    }

    private func isCurrentSelection(_ trip: SavedTrip) -> Bool {
        guard case .trip(let id) = selection else { return false }
        return id == trip.id
    }

    /// Cancels any in-flight fetch and starts a fresh one for the current selection.
    /// Clears stale data immediately (unless cached) so switching trips doesn't
    /// leave the previous trip's departures on screen while the new ones load.
    private func beginFetch() {
        fetchTask?.cancel()
        guard let trip = selectedTrip else {
            journeys = []
            return
        }

        let cacheKey = "\(trip.origin.id)-\(trip.destination.id)"
        canLoadEarlier = true
        canLoadLater = true
        isLoadingEarlier = false
        isLoadingLater = false

        if let cached = journeyCache[cacheKey] {
            journeys = cached
            journeyError = nil
            isLoadingJourneys = false
        } else {
            journeys = []
            journeyError = nil
            isLoadingJourneys = true
        }

        fetchTask = Task {
            await loadInitial(trip: trip, cacheKey: cacheKey)
        }
    }

    private func loadInitial(trip: SavedTrip, cacheKey: String) async {
        do {
            let fresh = try await APIClient.shared.planTrip(
                originId: trip.origin.id,
                destinationId: trip.destination.id,
                maxJourneys: 8
            )
            guard !Task.isCancelled, isCurrentSelection(trip) else { return }
            journeys = fresh
            journeyCache[cacheKey] = fresh
            lastUpdated = Date()
        } catch {
            guard !Task.isCancelled, isCurrentSelection(trip) else { return }
            if journeys.isEmpty {
                journeyError = error.localizedDescription
            }
        }
        if isCurrentSelection(trip) {
            isLoadingJourneys = false
        }
    }

    /// Loads a page of departures that already left, anchored just before the
    /// earliest one currently shown, and prepends them.
    private func loadEarlier() {
        guard let trip = selectedTrip, !isLoadingEarlier, canLoadEarlier,
              let earliest = journeys.first,
              let anchor = TimeFormatting.parseTime(earliest.legs.first?.origin.departureTimePlanned)
        else { return }

        isLoadingEarlier = true
        let cacheKey = "\(trip.origin.id)-\(trip.destination.id)"

        Task {
            do {
                let fresh = try await APIClient.shared.planTrip(
                    originId: trip.origin.id,
                    destinationId: trip.destination.id,
                    date: anchor.addingTimeInterval(-60),
                    isDepartureTime: false,
                    maxJourneys: 6
                )
                if isCurrentSelection(trip) {
                    let existingKeys = Set(journeys.map(journeyKey))
                    let newOnes = fresh.filter { !existingKeys.contains(journeyKey($0)) }
                    if newOnes.isEmpty {
                        canLoadEarlier = false
                    } else {
                        journeys = sortedByDeparture(newOnes + journeys)
                        journeyCache[cacheKey] = journeys
                    }
                }
            } catch {
                // Transient failure — leave canLoadEarlier as-is so scrolling again retries.
            }
            if isCurrentSelection(trip) {
                isLoadingEarlier = false
            }
        }
    }

    /// Loads a page of upcoming departures beyond the latest one currently shown,
    /// and appends them.
    private func loadLater() {
        guard let trip = selectedTrip, !isLoadingLater, canLoadLater,
              let latest = journeys.last,
              let anchor = TimeFormatting.parseTime(latest.legs.first?.origin.departureTimePlanned)
        else { return }

        isLoadingLater = true
        let cacheKey = "\(trip.origin.id)-\(trip.destination.id)"

        Task {
            do {
                let fresh = try await APIClient.shared.planTrip(
                    originId: trip.origin.id,
                    destinationId: trip.destination.id,
                    date: anchor.addingTimeInterval(60),
                    isDepartureTime: true,
                    maxJourneys: 6
                )
                if isCurrentSelection(trip) {
                    let existingKeys = Set(journeys.map(journeyKey))
                    let newOnes = fresh.filter { !existingKeys.contains(journeyKey($0)) }
                    if newOnes.isEmpty {
                        canLoadLater = false
                    } else {
                        journeys = sortedByDeparture(journeys + newOnes)
                        journeyCache[cacheKey] = journeys
                    }
                }
            } catch {
                // Transient failure — leave canLoadLater as-is so scrolling again retries.
            }
            if isCurrentSelection(trip) {
                isLoadingLater = false
            }
        }
    }

    private func sortedByDeparture(_ journeys: [Journey]) -> [Journey] {
        journeys.sorted {
            ($0.legs.first?.origin.departureTimePlanned ?? "") < ($1.legs.first?.origin.departureTimePlanned ?? "")
        }
    }

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: " Station", with: "")
    }
}

// MARK: - Settings Sheet

private enum SettingsTab: Hashable {
    case menuBar
    case shortcuts
    case account
    case feedback
}

private enum FeedbackState: Equatable {
    case idle
    case submitting
    case success
    case error(String)
}

private struct SettingsSheet: View {
    var updaterController: SPUStandardUpdaterController
    var onDismiss: () -> Void
    @State private var selectedTab: SettingsTab = .menuBar
    @State private var showSignOutAlert = false
    @State private var feedbackMessage = ""
    @State private var feedbackState: FeedbackState = .idle

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            VStack(alignment: .leading, spacing: 4) {
                // Back button
                AppButton(systemImage: "chevron.left", variant: .subtle) {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.bottom, 8)

                AppButton("Menu Bar", systemImage: "menubar.rectangle", variant: .subtle, isActive: selectedTab == .menuBar, fullWidth: true) {
                    selectedTab = .menuBar
                }
                AppButton("Shortcuts", systemImage: "command", variant: .subtle, isActive: selectedTab == .shortcuts, fullWidth: true) {
                    selectedTab = .shortcuts
                }
                AppButton("Account", systemImage: "person.circle", variant: .subtle, isActive: selectedTab == .account, fullWidth: true) {
                    selectedTab = .account
                }
                AppButton("Feedback", systemImage: "bubble.left", variant: .subtle, isActive: selectedTab == .feedback, fullWidth: true) {
                    selectedTab = .feedback
                    feedbackMessage = ""
                    feedbackState = .idle
                }

                Spacer()

                // Check for updates
                AppButton("Check for Updates", systemImage: "arrow.clockwise", variant: .subtle, fullWidth: true) {
                    onDismiss()
                    updaterController.checkForUpdates(nil)
                }
            }
            .padding(8)
            .frame(width: 190)

            // Settings content
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text(selectedTab == .menuBar ? "Menu Bar" : selectedTab == .shortcuts ? "Keyboard Shortcuts" : selectedTab == .account ? "Account" : "Feedback")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, 20)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .menuBar:
                            menuBarSettings
                        case .shortcuts:
                            shortcutsSettings
                        case .account:
                            accountSettings
                        case .feedback:
                            feedbackContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appCard(cornerRadius: UIRadius.sheetCard)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
            .padding(.top, 8)
        }
        .background(AppColors.sidebarBackground)
    }

    // MARK: - Menu Bar Settings

    private var menuBarSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview upcoming departure in menu bar")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.primaryText)

            SettingsToggle("Departure time", key: .departureTime)
            SettingsToggle("Countdown", key: .countdown)
        }
    }

    // MARK: - Keyboard Shortcuts Settings

    private var shortcutsSettings: some View {
        VStack(spacing: 0) {
            shortcutRow("New trip", keys: ["N"])
            Divider()
            shortcutRow("Settings", keys: ["\u{2318}", ","])
            Divider()
            shortcutRow("Refresh departures", keys: ["\u{2318}", "R"])
            Divider()
            shortcutRow("Previous trip", keys: ["\u{2191}"])
            Divider()
            shortcutRow("Next trip", keys: ["\u{2193}"])
            Divider()
            shortcutRow("Swap direction", keys: ["\u{2318}", "S"])
            Divider()
            shortcutRow("Delete trip", keys: ["\u{2318}", "\u{232B}"])
        }
    }

    // MARK: - Account Settings

    private var accountSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Signed-in email
            if let email = AuthManager.shared.cachedUser?.email {
                HStack {
                    Text("Signed in as")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.tertiaryText)
                    Spacer()
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(12)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: UIRadius.innerTile))
            }

            // License status
            if let user = AuthManager.shared.cachedUser {
                if user.isPurchased {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))
                        Text("Purchased")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.primaryText)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))
                        Text("No active license")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.primaryText)
                    }

                    AppButton("Buy — $5 \u{2192}", variant: .secondary, fullWidth: true) {
                        Task { await openCheckout() }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Signing out will require you to sign back in to use All Aboard.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                AppButton("Sign Out", variant: .secondary, fullWidth: true) {
                    showSignOutAlert = true
                }
            }
        }
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                AuthManager.shared.signOut()
                NSApp.terminate(nil)
            }
        } message: {
            Text("You will need to sign back in to use All Aboard.")
        }
    }

    // MARK: - Feedback Settings

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch feedbackState {
            case .success:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text("Thanks for the feedback!")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primaryText)
                    Text("We appreciate you taking the time to share your thoughts.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.tertiaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's on your mind?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.primaryText)

                    TextEditor(text: $feedbackMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.primaryText)
                        .scrollContentBackground(.hidden)
                        .background(AppColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: UIRadius.innerTile))
                        .overlay(
                            RoundedRectangle(cornerRadius: UIRadius.innerTile)
                                .stroke(AppColors.contentBorder, lineWidth: 1)
                        )
                        .frame(height: 100)
                        .disabled(feedbackState == .submitting)
                }

                if case .error(let msg) = feedbackState {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Spacer()
                    if feedbackState == .submitting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    AppButton("Send Feedback", variant: .primary) {
                        Task { await submitFeedback() }
                    }
                    .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || feedbackState == .submitting)
                }
            }
        }
    }

    private func submitFeedback() async {
        let trimmed = feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        feedbackState = .submitting

        var request = URLRequest(url: URL(string: "https://speaking.computer/feedback")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "message": trimmed,
            "email": AuthManager.shared.cachedUser?.email ?? "",
            "app": "All Aboard"
        ]

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 {
                feedbackState = .success
            } else {
                feedbackState = .error("Something went wrong. Please try again.")
            }
        } catch {
            feedbackState = .error("Couldn't send feedback. Check your connection.")
        }
    }

    private func openCheckout() async {
        guard let url = try? await AuthManager.shared.checkoutURL() else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Keyboard Shortcuts Settings

    private func shortcutRow(_ action: String, keys: [String]) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.primaryText)
            Spacer()
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: UIRadius.keycap))
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Settings Toggle

private struct SettingsToggle: View {
    enum Key {
        case departureTime
        case countdown
    }

    let label: String
    let key: Key
    @State private var isOn: Bool

    init(_ label: String, key: Key) {
        self.label = label
        self.key = key
        switch key {
        case .departureTime: self._isOn = State(initialValue: AppSettings.showDepartureTimeInMenuBar)
        case .countdown: self._isOn = State(initialValue: AppSettings.showCountdownInMenuBar)
        }
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .font(.system(size: 13))
            .onChange(of: isOn) { _, val in
                switch key {
                case .departureTime: AppSettings.showDepartureTimeInMenuBar = val
                case .countdown: AppSettings.showCountdownInMenuBar = val
                }
            }
    }
}

// MARK: - Add Trip Sheet

private struct AddTripSheet: View {
    var store: TripStore
    var viewModel: TripCreationViewModel
    var onTripsChanged: (() -> Void)?
    var onDone: (String?) -> Void

    @State private var originInput = ""
    @State private var destinationInput = ""
    @State private var selectedResultIndex = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AppButton("Cancel", variant: .subtle) { onDone(nil) }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Text("New Trip")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        stepBadge(number: 1, label: "Origin", isActive: viewModel.selectedOrigin == nil)
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(AppColors.tertiaryText)
                        stepBadge(number: 2, label: "Destination", isActive: viewModel.selectedOrigin != nil)
                    }

                    if let origin = viewModel.selectedOrigin {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill").font(.system(size: 16)).foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("From").font(.system(size: 10)).foregroundStyle(AppColors.tertiaryText)
                                Text(displayName(origin.disassembledName ?? origin.name)).font(.system(size: 14, weight: .semibold))
                            }
                            Spacer()
                            AppButton("Change", variant: .secondary) {
                                viewModel.goBack(); originInput = ""; destinationInput = ""; selectedResultIndex = 0; focused = true
                            }
                        }
                        .padding(12)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: UIRadius.innerTile))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.selectedOrigin == nil ? "Search for origin station" : "Now search for destination")
                            .font(.system(size: 12)).foregroundStyle(AppColors.tertiaryText)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(AppColors.tertiaryText)
                            TextField("Station name\u{2026}", text: viewModel.selectedOrigin == nil ? $originInput : $destinationInput)
                                .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                                .onSubmit { confirmSelection() }
                                .onKeyPress(.downArrow) { nudge(1); return .handled }
                                .onKeyPress(.upArrow) { nudge(-1); return .handled }
                        }
                        .padding(10)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: UIRadius.innerTile))
                    }
                    .onChange(of: originInput) { _, val in
                        guard viewModel.selectedOrigin == nil else { return }
                        viewModel.searchQuery = val; viewModel.step = .origin; viewModel.search(); selectedResultIndex = 0
                    }
                    .onChange(of: destinationInput) { _, val in
                        guard viewModel.selectedOrigin != nil else { return }
                        viewModel.searchQuery = val; viewModel.step = .destination; viewModel.search(); selectedResultIndex = 0
                    }

                    if viewModel.isSearching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Searching\u{2026}").font(.system(size: 12)).foregroundStyle(AppColors.tertiaryText)
                        }
                    }

                    if !viewModel.searchResults.isEmpty {
                        let results = Array(viewModel.searchResults.prefix(8))
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, stop in
                                Button(action: { selectStop(stop) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(displayName(stop.disassembledName ?? stop.name))
                                                .font(.system(size: 13, weight: .medium)).foregroundStyle(AppColors.primaryText)
                                            if let loc = stop.properties?.mainLocality ?? stop.parent?.name {
                                                Text(loc).font(.system(size: 11)).foregroundStyle(AppColors.tertiaryText)
                                            }
                                        }
                                        Spacer()
                                        if index == selectedResultIndex {
                                            Image(systemName: "return").font(.system(size: 10)).foregroundStyle(AppColors.tertiaryText)
                                        }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(index == selectedResultIndex ? Color.accentColor.opacity(0.1) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: UIRadius.innerTile))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            viewModel.reset(); originInput = ""; destinationInput = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }

    private func selectStop(_ stop: StopLocation) {
        if viewModel.selectedOrigin == nil {
            originInput = stop.disassembledName ?? stop.name
            viewModel.selectOrigin(stop); selectedResultIndex = 0; focused = true
        } else {
            viewModel.selectDestination(stop); onTripsChanged?()
            onDone(store.savedTrips.last?.id)
        }
    }

    private func confirmSelection() {
        let results = Array(viewModel.searchResults.prefix(8))
        guard selectedResultIndex < results.count else { return }
        selectStop(results[selectedResultIndex])
    }

    private func nudge(_ delta: Int) {
        let count = min(viewModel.searchResults.count, 8)
        guard count > 0 else { return }
        selectedResultIndex = max(0, min(count - 1, selectedResultIndex + delta))
    }

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: " Station", with: "")
    }

    private func stepBadge(number: Int, label: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isActive ? Color.white : AppColors.secondaryText.opacity(0.5))
                .frame(width: 18, height: 18)
                .background { Circle().fill(isActive ? Color.accentColor : AppColors.secondaryText.opacity(0.15)) }
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? AppColors.primaryText : AppColors.tertiaryText)
        }
    }
}

