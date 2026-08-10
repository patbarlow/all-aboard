import SwiftUI

struct TripDetailView: View {
    let trip: SavedTrip
    var journeys: [Journey]
    var isLoading: Bool
    var errorMessage: String?
    var canLoadEarlier: Bool = false
    var canLoadLater: Bool = false
    var isLoadingEarlier: Bool = false
    var isLoadingLater: Bool = false
    var onSwap: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onLoadEarlier: (() -> Void)?
    var onLoadLater: (() -> Void)?

    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack(alignment: .leading, spacing: 8) {
                routeHeader(scrollProxy: scrollProxy)

                ScrollView {
                    departuresContent
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .appCard(cornerRadius: UIRadius.parentCard)
            }
            .onChange(of: journeys.first?.stableKey) { oldFirstKey, _ in
                // Loading earlier departures prepends rows above what's visible —
                // re-anchor the scroll position so the view doesn't jump.
                guard let oldFirstKey, journeys.contains(where: { $0.stableKey == oldFirstKey }) else { return }
                scrollProxy.scrollTo(oldFirstKey, anchor: .top)
            }
        }
    }

    // MARK: - Route Header

    private func routeHeader(scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            Text("\(displayName(trip.origin.name)) \u{2192} \(displayName(trip.destination.name))")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)

            Spacer()

            AppButton(systemImage: "arrow.left.arrow.right", variant: .subtle) {
                onSwap?()
            }
            .help("Swap Direction")

            AppButton(systemImage: "location.fill", variant: .subtle) {
                let target = journeys.first(where: { !$0.isPast })?.stableKey ?? journeys.last?.stableKey
                if let target {
                    withAnimation { scrollProxy.scrollTo(target, anchor: .top) }
                }
            }
            .help("Jump back to now")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // MARK: - Departures

    @ViewBuilder
    private var departuresContent: some View {
        if isLoading && journeys.isEmpty {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading departures\u{2026}")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 60)
        } else if let error = errorMessage, journeys.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.tertiaryText)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 60)
        } else {
            VStack(spacing: 8) {
                // Explicit, tap-to-load — auto-loading here caused a feedback loop
                // (loading kept re-triggering and snapping the scroll position around).
                loadEarlierRow

                ForEach(journeys, id: \.stableKey) { journey in
                    DepartureCard(journey: journey)
                }

                // Appending below the fold is safe to auto-load as it scrolls into view.
                loadMoreRow(isLoading: isLoadingLater, canLoad: canLoadLater, action: onLoadLater)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var loadEarlierRow: some View {
        if isLoadingEarlier {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else if canLoadEarlier {
            Button {
                onLoadEarlier?()
            } label: {
                Text("Show earlier departures")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func loadMoreRow(isLoading: Bool, canLoad: Bool, action: (() -> Void)?) -> some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else if canLoad {
            // Invisible sentinel — loads the next page automatically as it scrolls into view.
            Color.clear
                .frame(height: 1)
                .onAppear { action?() }
        }
    }

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: " Station", with: "")
    }
}

// MARK: - Departure Card

struct DepartureCard: View {
    let journey: Journey

    private var firstLeg: Leg? { journey.legs.first }
    private var lastLeg: Leg? { journey.legs.last }
    private var transportLeg: Leg? { journey.legs.first { $0.transportation != nil } }

    private var departureTime: String? { firstLeg?.origin.departureTimePlanned }
    private var arrivalTime: String? { lastLeg?.destination.arrivalTimePlanned }

    private var platform: String? {
        let raw = transportLeg?.origin.properties?.platformName
            ?? transportLeg?.origin.properties?.platform
        guard let raw, !raw.isEmpty else { return nil }
        return raw.lowercased().hasPrefix("platform") ? raw : "Platform \(raw)"
    }

    private var duration: String? {
        guard let dep = TimeFormatting.parseTime(departureTime),
              let arr = TimeFormatting.parseTime(arrivalTime) else { return nil }
        let seconds = Int(arr.timeIntervalSince(dep))
        guard seconds > 0 else { return nil }
        return TimeFormatting.formatDuration(seconds)
    }

    private var transportMode: TransportMode? {
        guard let pc = transportLeg?.transportation?.product?.productClass else { return nil }
        return TransportMode(rawValue: pc)
    }

    private var isPast: Bool { journey.isPast }

    private var isCancelled: Bool { journey.realtimeStatus.isCancelled }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(TimeFormatting.formatTime(departureTime)) \u{2192} \(TimeFormatting.formatTime(arrivalTime))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColors.primaryText)
                    .strikethrough(isCancelled)

                HStack(spacing: 5) {
                    if let duration {
                        Text(duration)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.secondaryText)
                            .strikethrough(isCancelled)
                    }
                    if let platform {
                        Text("\u{00b7}").foregroundStyle(AppColors.tertiaryText)
                        Text(platform)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.secondaryText)
                            .strikethrough(isCancelled)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if isPast {
                    Text(TimeFormatting.formatTimeAgo(firstLeg?.origin.departureTimeEstimated ?? departureTime))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppColors.tertiaryText)
                } else {
                    let countdown = TimeFormatting.formatTimeUntil(firstLeg?.origin.departureTimeEstimated ?? departureTime)
                    Text(countdown)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppColors.primaryText)
                }

                switch journey.realtimeStatus {
                case .onTime:
                    Text("On time")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.secondaryText)
                case .delayed(let minutes):
                    Text("\(minutes) min\(minutes == 1 ? "" : "s") late")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                case .cancelled:
                    Text("Cancelled")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                case .realtimeUnavailable, .unknown:
                    Text("Realtime unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.cardBackground)
        )
        .opacity(isPast ? 0.55 : 1)
    }
}
