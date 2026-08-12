import SwiftUI

struct OnboardingView: View {
    var store: TripStore
    var menuBarViewModel: MenuBarViewModel
    var onContinueToMenuBarTip: () -> Void
    var onFinished: () -> Void

    @State private var viewModel: TripCreationViewModel
    @State private var step: Step = .addTrip
    @State private var originInput = ""
    @State private var destinationInput = ""
    @State private var selectedResultIndex = 0
    @State private var hasSavedTrip = false
    @State private var showCountdown = AppSettings.showCountdownInMenuBar
    @State private var showDepartureTime = AppSettings.showDepartureTimeInMenuBar
    @FocusState private var focusedField: Field?

    private enum Step: Int, CaseIterable { case addTrip, menuBarTip }
    private enum Field { case origin, destination }

    init(store: TripStore, menuBarViewModel: MenuBarViewModel, onContinueToMenuBarTip: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.store = store
        self.menuBarViewModel = menuBarViewModel
        self.onContinueToMenuBarTip = onContinueToMenuBarTip
        self.onFinished = onFinished
        self._viewModel = State(initialValue: TripCreationViewModel(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                Group {
                    switch step {
                    case .addTrip:
                        addTripStep
                    case .menuBarTip:
                        menuBarTipStep
                    }
                }
                .padding(24)
            }

            footer
        }
        .frame(width: 360, height: 520)
        .background(AppColors.sidebarBackground)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .origin
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "tram.fill")
                .font(.system(size: 40))
                .foregroundColor(.primary)
            Text(headline)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var headline: String {
        switch step {
        case .addTrip: return "Add your first trip"
        case .menuBarTip: return "You're all set"
        }
    }

    // MARK: - Step 1: Add Trip

    private var addTripStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            originFieldGroup

            if focusedField == .origin && hasSearchContent {
                inlineSearchResults
                    .padding(.top, 8)
            }

            Spacer().frame(height: 12)

            destinationFieldGroup

            if focusedField == .destination && hasSearchContent {
                inlineSearchResults
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 12)
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
        .animation(.spring(duration: 0.3), value: hasSearchContent)
    }

    @ViewBuilder
    private var originFieldGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("From")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            if hasSavedTrip || viewModel.selectedOrigin != nil {
                HStack {
                    Text(displayName(originInput))
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if !hasSavedTrip {
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
                }
            } else {
                TextField("Search station", text: $originInput)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .focused($focusedField, equals: .origin)
                    .onSubmit { confirmSelection() }
                    .onKeyPress(.downArrow) { nudgeSelection(1); return .handled }
                    .onKeyPress(.upArrow) { nudgeSelection(-1); return .handled }
            }
        }
    }

    @ViewBuilder
    private var destinationFieldGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("To")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            if hasSavedTrip {
                Text(displayName(destinationInput))
                    .font(.system(size: 16, weight: .semibold))
            } else if viewModel.selectedOrigin == nil {
                Text("Search station")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.tertiaryText)
            } else {
                TextField("Search station", text: $destinationInput)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .focused($focusedField, equals: .destination)
                    .onSubmit { confirmSelection() }
                    .onKeyPress(.downArrow) { nudgeSelection(1); return .handled }
                    .onKeyPress(.upArrow) { nudgeSelection(-1); return .handled }
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

    private func selectStop(_ stop: StopLocation) {
        if focusedField == .origin {
            originInput = stop.disassembledName ?? stop.name
            viewModel.selectOrigin(stop)
            selectedResultIndex = 0
            focusedField = .destination
        } else {
            destinationInput = stop.disassembledName ?? stop.name
            viewModel.selectDestination(stop)
            selectedResultIndex = 0
            focusedField = nil
            hasSavedTrip = true
            menuBarViewModel.startAutoRefreshIfNeeded()
        }
    }

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: " Station", with: "")
    }

    // MARK: - Step 2: Menu Bar Tip

    private var menuBarTipStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All Aboard can show upcoming departures for this trip in the top right of your screen. Set how much, or how little information is shown by adjusting the toggles below.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Countdown", isOn: $showCountdown)
                    .onChange(of: showCountdown) { _, val in AppSettings.showCountdownInMenuBar = val }
                Toggle("Departure time", isOn: $showDepartureTime)
                    .onChange(of: showDepartureTime) { _, val in AppSettings.showDepartureTimeInMenuBar = val }
            }
            .font(.system(size: 13))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(cornerRadius: 12)

            Text("You can change this later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.tertiaryText)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        ZStack {
            progressDots

            HStack {
                AppButton("Back", variant: .secondary) { goBack() }
                    .opacity(step == .addTrip ? 0 : 1)
                    .disabled(step == .addTrip)

                Spacer()

                AppButton(continueLabel, variant: .primary) {
                    advance()
                }
                .keyboardShortcut(.return)
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { candidate in
                Circle()
                    .fill(candidate == step ? AppColors.primaryText : AppColors.contentBorder)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var continueLabel: String {
        switch step {
        case .addTrip: return "Continue"
        case .menuBarTip: return "Get Started"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .addTrip: return hasSavedTrip
        case .menuBarTip: return true
        }
    }

    private func advance() {
        switch step {
        case .addTrip:
            step = .menuBarTip
            onContinueToMenuBarTip()
        case .menuBarTip:
            onFinished()
        }
    }

    private func goBack() {
        step = .addTrip
    }
}
