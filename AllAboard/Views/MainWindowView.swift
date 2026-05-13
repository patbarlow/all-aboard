import SwiftUI
import Sparkle

// Visual radius constants for consistent rounding
private struct UIRadius {
    static let parentCard: CGFloat = 8    // large containers (main content, settings sheet)
    static let sheetContainer: CGFloat = 8 // outer settings sheet container
    static let sheetInset: CGFloat = 8      // sheet content padding from edges
    static let sheetCard: CGFloat = 8      // inner card inside settings sheet
    static let innerTile: CGFloat = 8     // smaller tiles inside cards (license key, input rows)
    static let keycap: CGFloat = 8        // tiny keycap-like elements
}

// Reusable card styling for content surfaces
private struct AppCardModifier: ViewModifier {
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

private extension View {
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

    // Drag reorder state
    @State private var draggingTripId: String?
    @State private var dragCurrentIndex: Int = 0
    @State private var dragAccumulated: CGFloat = 0

    private let rowHeight: CGFloat = 36 // 32pt button + 4pt spacing

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

            // Content card
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appCard(cornerRadius: UIRadius.parentCard)
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
                Task { await fetchJourneys() }
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
                    ForEach(Array(store.savedTrips.enumerated()), id: \.element.id) { index, trip in
                        let isDragging = draggingTripId == trip.id

                        AppButton(
                            "\(displayName(trip.origin.name)) \u{2192} \(displayName(trip.destination.name))",
                            variant: .subtle,
                            isActive: selection == .trip(trip.id),
                            fullWidth: true
                        ) {
                            selection = .trip(trip.id)
                        }
                        .opacity(isDragging ? 0.5 : 1)
                        .scaleEffect(isDragging ? 0.98 : 1)
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { value in
                                    if draggingTripId == nil {
                                        draggingTripId = trip.id
                                        dragCurrentIndex = index
                                        dragAccumulated = 0
                                    }
                                    // Accumulate drag and check if we crossed a row threshold
                                    let delta = value.translation.height - dragAccumulated
                                    if delta > rowHeight / 2, dragCurrentIndex < store.savedTrips.count - 1 {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            store.savedTrips.move(fromOffsets: IndexSet(integer: dragCurrentIndex), toOffset: dragCurrentIndex + 2)
                                        }
                                        dragCurrentIndex += 1
                                        dragAccumulated += rowHeight
                                    } else if delta < -rowHeight / 2, dragCurrentIndex > 0 {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            store.savedTrips.move(fromOffsets: IndexSet(integer: dragCurrentIndex), toOffset: dragCurrentIndex - 1)
                                        }
                                        dragCurrentIndex -= 1
                                        dragAccumulated -= rowHeight
                                    }
                                }
                                .onEnded { _ in
                                    draggingTripId = nil
                                    dragAccumulated = 0
                                    store.persistOrder()
                                    onTripsChanged?()
                                }
                        )
                        .contextMenu {
                            Button {
                                store.reverseTrip(id: trip.id)
                                onTripsChanged?()
                                if case .trip(trip.id) = selection { Task { await fetchJourneys() } }
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
                onSwap: {
                    store.reverseTrip(id: trip.id)
                    onTripsChanged?()
                    Task { await fetchJourneys() }
                },
                onRefresh: {
                    Task { await fetchJourneys() }
                }
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
    }

    // MARK: - Data

    private func fetchJourneys() async {
        guard let trip = selectedTrip else { return }

        let cacheKey = "\(trip.origin.id)-\(trip.destination.id)"

        // Show cached data instantly if available
        if let cached = journeyCache[cacheKey] {
            journeys = cached
            journeyError = nil
            // Still refresh in background but don't show loading state
            isLoadingJourneys = false
        } else {
            isLoadingJourneys = true
            journeyError = nil
        }

        do {
            let fresh = try await APIClient.shared.planTrip(
                originId: trip.origin.id,
                destinationId: trip.destination.id,
                maxJourneys: 12
            )
            journeys = fresh
            journeyCache[cacheKey] = fresh
            lastUpdated = Date()
        } catch {
            if journeys.isEmpty {
                journeyError = error.localizedDescription
            }
        }
        isLoadingJourneys = false
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

            // Subscription status
            if let user = AuthManager.shared.cachedUser {
                if user.isTrialing {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Free trial")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.primaryText)
                                let days = user.trialDaysRemaining
                                Text(days == 0 ? "Expires today" : days == 1 ? "1 day remaining" : "\(days) days remaining")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.tertiaryText)
                            }
                        }

                        AppButton("Upgrade — $4/month \u{2192}", variant: .secondary, fullWidth: true) {
                            Task { await openCheckout() }
                        }
                    }
                } else if user.isSubscribed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))
                        Text("Subscription active")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.primaryText)
                    }

                    AppButton("Manage subscription \u{2192}", variant: .secondary, fullWidth: true) {
                        Task { await openPortal() }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))
                        Text("No active subscription")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.primaryText)
                    }

                    AppButton("Subscribe — $4/month \u{2192}", variant: .secondary, fullWidth: true) {
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

    private func openPortal() async {
        guard let url = try? await AuthManager.shared.portalURL() else { return }
        NSWorkspace.shared.open(url)
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

