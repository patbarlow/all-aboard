import SwiftUI

struct TripCreationView: View {
    var store: TripStore
    var onTripsChanged: () -> Void
    @State private var viewModel: TripCreationViewModel
    @State private var isDrafting = false
    @State private var selection: Set<String> = []
    @State private var originInput = ""
    @State private var destinationInput = ""
    @State private var selectedResultIndex = 0
    @State private var draggingTripId: String?
    @State private var dragOriginIndex: Int = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var releaseChannel = AppSettings.releaseChannel
    @State private var betaFeaturesEnabled = AppSettings.enableBetaFeatures
    @State private var selectedTab: Tab = .trips
    @FocusState private var focusedField: DraftField?

    private enum DraftField: Hashable {
        case origin
        case destination
    }

    private enum Tab: Hashable {
        case trips
        case settings
    }

    private let cardHeight: CGFloat = 103 // card (~95) + spacing (8)

    init(store: TripStore, onTripsChanged: @escaping () -> Void) {
        self.store = store
        self.onTripsChanged = onTripsChanged
        self._viewModel = State(initialValue: TripCreationViewModel(store: store))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            tripsTab
                .tabItem { Label("Trips", systemImage: "tram.fill") }
                .tag(Tab.trips)
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .frame(width: 420, height: 520)
    }

    // MARK: - Trips Tab

    private var tripsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    oneOffQuerySection

                    if isDrafting {
                        draftCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !store.savedTrips.isEmpty {
                        savedTripsSection
                    } else if !isDrafting {
                        emptyState
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.removeAll() }
            .animation(.spring(duration: 0.35), value: isDrafting)
            .animation(.spring(duration: 0.3), value: hasSearchContent)
            .navigationTitle("All Aboard")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    toolbarContent
                }
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                releaseChannelSection
                if betaFeaturesEnabled {
                    betaFeaturesSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var oneOffQuerySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Search")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)

                TextField("e.g. Strathfield to Chatswood after 5pm", text: $viewModel.naturalLanguageQuery)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        viewModel.runNaturalLanguageQuery()
                    }
                    .onKeyPress(.escape) {
                        viewModel.naturalLanguageQuery = ""
                        viewModel.clearOneOffResults()
                        return .handled
                    }
            }

            if viewModel.isRunningNaturalLanguageQuery {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching train times…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            if let origin = viewModel.oneOffOrigin, let destination = viewModel.oneOffDestination {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(displayName(origin.disassembledName ?? origin.name)) → \(displayName(destination.disassembledName ?? destination.name))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save Trip") {
                            viewModel.saveOneOffTrip()
                            onTripsChanged()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                    }
                    if let description = viewModel.oneOffDescription {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
            }

            if let error = viewModel.naturalLanguageError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            if !viewModel.oneOffJourneys.isEmpty {
                VStack(spacing: 6) {
                    ForEach(viewModel.oneOffJourneys) { journey in
                        oneOffJourneyRow(journey)
                    }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.35), value: viewModel.oneOffJourneys.map(\.id))
        .animation(.spring(duration: 0.3), value: viewModel.isRunningNaturalLanguageQuery)
    }

    private func oneOffJourneyRow(_ journey: Journey) -> some View {
        let firstLeg = journey.legs.first
        let lastLeg = journey.legs.last
        let transportLeg = journey.legs.first { $0.transportation != nil }
        let departTime = TimeFormatting.formatTime(firstLeg?.origin.departureTimePlanned)
        let arriveTime = TimeFormatting.formatTime(lastLeg?.destination.arrivalTimePlanned)
        let timeUntil = TimeFormatting.formatTimeUntil(firstLeg?.origin.departureTimePlanned)
        let subtitle = journeySubtitle(for: journey, transportLeg: transportLeg)
        let realtimeStatus = realtimeStatus(for: transportLeg?.origin ?? firstLeg?.origin)

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(departTime) → \(arriveTime)")
                    .font(.subheadline.monospacedDigit())
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeUntil)
                    .font(.system(size: 12, weight: .semibold))
                if !realtimeStatus.isEmpty {
                    Text(realtimeStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(realtimeStatus.contains("late") ? .red : .secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func journeySubtitle(for journey: Journey, transportLeg: Leg?) -> String {
        let duration = journeyDurationText(for: journey)
        let rawPlatform = transportLeg?.origin.properties?.platformName
            ?? transportLeg?.origin.properties?.platform
        guard let rawPlatform, !rawPlatform.isEmpty else {
            return duration
        }

        let platform = rawPlatform.lowercased().hasPrefix("platform") ? rawPlatform : "Platform \(rawPlatform)"
        if duration.isEmpty { return platform }
        return "\(duration) · \(platform)"
    }

    private func journeyDurationText(for journey: Journey) -> String {
        guard let departDate = TimeFormatting.parseTime(journey.legs.first?.origin.departureTimePlanned),
              let arriveDate = TimeFormatting.parseTime(journey.legs.last?.destination.arrivalTimePlanned) else {
            return ""
        }
        let seconds = Int(arriveDate.timeIntervalSince(departDate))
        guard seconds > 0 else { return "" }
        return TimeFormatting.formatDuration(seconds)
    }

    private func realtimeStatus(for origin: LegLocation?) -> String {
        guard let planned = TimeFormatting.parseTime(origin?.departureTimePlanned),
              let estimated = TimeFormatting.parseTime(origin?.departureTimeEstimated) else {
            return ""
        }

        let diffMins = Int(round(estimated.timeIntervalSince(planned) / 60))
        if diffMins <= 0 { return "On time" }
        return "\(diffMins) min\(diffMins == 1 ? "" : "s") late"
    }

    // MARK: - Helpers

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: " Station", with: "")
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarContent: some View {
        if selection.isEmpty {
            Button {
                viewModel.reset()
                originInput = ""
                destinationInput = ""
                selectedResultIndex = 0
                isDrafting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .origin
                }
            } label: {
                Image(systemName: "plus")
            }
        } else {
            ControlGroup {
                Button {
                    duplicateSelected()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Draft Card (search results inline)

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            originFieldGroup

            if focusedField == .origin && hasSearchContent {
                inlineSearchResults
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            Spacer().frame(height: 12)

            destinationFieldGroup

            if focusedField == .destination && hasSearchContent {
                inlineSearchResults
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.3), value: hasSearchContent)
        .animation(.spring(duration: 0.3), value: viewModel.searchResults.count)
        .onChange(of: originInput) { _, newValue in
            guard focusedField == .origin, viewModel.selectedOrigin == nil else { return }
            viewModel.searchQuery = newValue
            viewModel.step = .origin
            viewModel.search()
        }
        .onChange(of: destinationInput) { _, newValue in
            guard focusedField == .destination else { return }
            viewModel.searchQuery = newValue
            viewModel.step = .destination
            viewModel.search()
        }
        .onChange(of: viewModel.searchResults.map(\.id)) { _, _ in
            selectedResultIndex = 0
        }
    }

    @ViewBuilder
    private var originFieldGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("From")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            if viewModel.selectedOrigin != nil {
                HStack {
                    Text(displayName(originInput))
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button {
                        viewModel.selectedOrigin = nil
                        originInput = ""
                        viewModel.searchResults = []
                        selectedResultIndex = 0
                        focusedField = .origin
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                TextField("Search station", text: $originInput)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .origin)
                    .onSubmit { confirmSelection() }
                    .onKeyPress(.downArrow) { nudgeSelection(1); return .handled }
                    .onKeyPress(.upArrow) { nudgeSelection(-1); return .handled }
                    .onKeyPress(.escape) { cancelDraft(); return .handled }
            }
        }
    }

    @ViewBuilder
    private var destinationFieldGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("To")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            if viewModel.selectedOrigin == nil {
                Text("Search station")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.quaternary)
            } else {
                TextField("Search station", text: $destinationInput)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .destination)
                    .onSubmit { confirmSelection() }
                    .onKeyPress(.downArrow) { nudgeSelection(1); return .handled }
                    .onKeyPress(.upArrow) { nudgeSelection(-1); return .handled }
                    .onKeyPress(.escape) { cancelDraft(); return .handled }
            }
        }
    }

    private var hasSearchContent: Bool {
        viewModel.isSearching || !viewModel.searchResults.isEmpty
    }

    @ViewBuilder
    private var inlineSearchResults: some View {
        if viewModel.isSearching {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if !viewModel.searchResults.isEmpty {
            let results = Array(viewModel.searchResults.prefix(6))
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, stop in
                    Button {
                        selectStop(stop)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName(stop.disassembledName ?? stop.name))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            if let locality = stop.properties?.mainLocality ?? stop.parent?.name {
                                Text(locality)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            index == selectedResultIndex
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func nudgeSelection(_ delta: Int) {
        let count = min(viewModel.searchResults.count, 6)
        guard count > 0 else { return }
        selectedResultIndex = max(0, min(count - 1, selectedResultIndex + delta))
    }

    private func confirmSelection() {
        let results = Array(viewModel.searchResults.prefix(6))
        guard selectedResultIndex < results.count else { return }
        selectStop(results[selectedResultIndex])
    }

    private func cancelDraft() {
        isDrafting = false
        viewModel.reset()
        originInput = ""
        destinationInput = ""
        focusedField = nil
    }

    private func selectStop(_ stop: StopLocation) {
        if focusedField == .origin {
            originInput = stop.disassembledName ?? stop.name
            viewModel.selectOrigin(stop)
            selectedResultIndex = 0
            focusedField = .destination
        } else {
            destinationInput = stop.disassembledName ?? stop.name
            viewModel.selectDestination(stop)
            isDrafting = false
            originInput = ""
            destinationInput = ""
            focusedField = nil
            onTripsChanged()
        }
    }

    // MARK: - Saved Trips (single column, drag to reorder)

    private var dropTargetIndex: Int? {
        guard draggingTripId != nil else { return nil }
        let proposed = dragOriginIndex + Int(round(dragTranslation / cardHeight))
        let clamped = max(0, min(store.savedTrips.count - 1, proposed))
        return clamped == dragOriginIndex ? nil : clamped
    }

    @ViewBuilder
    private var savedTripsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Saved Trips")
                    .font(.headline)
                Text("\(store.savedTrips.count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(Array(store.savedTrips.enumerated()), id: \.element.id) { index, trip in
                    let isDragging = draggingTripId == trip.id

                    // Insertion line before this card
                    if let target = dropTargetIndex, target == index, target < dragOriginIndex {
                        insertionLine
                    }

                    tripCard(trip)
                        .opacity(isDragging ? 0.35 : 1.0)
                        .overlay {
                            if isDragging {
                                tripCard(trip)
                                    .scaleEffect(1.03)
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                                    .offset(y: dragTranslation)
                            }
                        }
                        .zIndex(isDragging ? 1 : 0)
                        .gesture(
                            TapGesture().onEnded { handleCardTap(trip.id) },
                            including: .gesture
                        )
                        .gesture(
                            DragGesture(minimumDistance: 14)
                                .onChanged { value in
                                    handleDragChanged(tripId: trip.id, index: index, translation: value.translation.height)
                                }
                                .onEnded { _ in
                                    handleDragEnded()
                                }
                        )

                    // Insertion line after this card
                    if let target = dropTargetIndex, target == index, target > dragOriginIndex {
                        insertionLine
                    }
                }
            }
            .animation(.spring(duration: 0.3), value: store.savedTrips.map(\.id))
        }
    }

    private var insertionLine: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(height: 3)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func handleDragChanged(tripId: String, index: Int, translation: CGFloat) {
        if draggingTripId == nil {
            draggingTripId = tripId
            dragOriginIndex = index
        }
        dragTranslation = translation
    }

    private func handleDragEnded() {
        guard let dragId = draggingTripId,
              let originIdx = store.savedTrips.firstIndex(where: { $0.id == dragId }),
              let target = dropTargetIndex else {
            draggingTripId = nil
            dragTranslation = 0
            return
        }

        withAnimation(.spring(duration: 0.3)) {
            if target < originIdx {
                store.savedTrips.move(fromOffsets: IndexSet(integer: originIdx), toOffset: target)
            } else {
                store.savedTrips.move(fromOffsets: IndexSet(integer: originIdx), toOffset: target + 1)
            }
        }

        draggingTripId = nil
        dragTranslation = 0
        store.persistOrder()
        onTripsChanged()
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tram")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("No saved trips yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 40)
    }

    // MARK: - Trip Card

    private func tripCard(_ trip: SavedTrip) -> some View {
        let isSelected = selection.contains(trip.id)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("From")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Text(displayName(trip.origin.name))
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("To")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Text(displayName(trip.destination.name))
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Selection

    private func handleCardTap(_ id: String) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) || modifiers.contains(.command) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else {
            if selection == [id] {
                selection.removeAll()
            } else {
                selection = [id]
            }
        }
    }

    // MARK: - Actions

    private func duplicateSelected() {
        let ids = selection
        for id in ids { store.duplicateTrip(id: id) }
        selection.removeAll()
        onTripsChanged()
    }

    private func deleteSelected() {
        let ids = selection
        for id in ids { store.removeTrip(id: id) }
        selection.removeAll()
        onTripsChanged()
    }

    private func reverseTrip(_ id: String) {
        store.reverseTrip(id: id)
        onTripsChanged()
    }

    // MARK: - Release Channels / Feature Flags

    private var releaseChannelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Release Channel")
                .font(.headline)

            Picker("Channel", selection: $releaseChannel) {
                Text("Stable").tag(ReleaseChannel.stable)
                Text("Beta").tag(ReleaseChannel.beta)
            }
            .pickerStyle(.segmented)
            .onChange(of: releaseChannel) { _, newValue in
                AppSettings.releaseChannel = newValue
            }

            Toggle("Enable beta feature toggles", isOn: $betaFeaturesEnabled)
                .onChange(of: betaFeaturesEnabled) { _, newValue in
                    AppSettings.enableBetaFeatures = newValue
                }

            Text("Restart the app after changing channel, then use “Check for Updates…” from the menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var betaFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Beta Tools")
                .font(.headline)
            Text("Use these while testing in-progress work.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Refresh departures now") {
                onTripsChanged()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    TripCreationView(store: TripStore(), onTripsChanged: {})
}
