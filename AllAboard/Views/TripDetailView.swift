import SwiftUI

struct TripDetailView: View {
    let trip: SavedTrip
    var journeys: [Journey]
    var isLoading: Bool
    var errorMessage: String?
    var onSwap: (() -> Void)?
    var onRefresh: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                routeHeader
                departuresContent
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Route Header

    private var routeHeader: some View {
        HStack(spacing: 0) {
            Text("\(displayName(trip.origin.name)) \u{2192} \(displayName(trip.destination.name))")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)

            Spacer()

            AppButton(systemImage: "arrow.left.arrow.right", variant: .subtle) {
                onSwap?()
            }
            .help("Swap Direction")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
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
                ForEach(Array(journeys.prefix(12).enumerated()), id: \.element.id) { _, journey in
                    DepartureCard(journey: journey)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
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

    private var delayMinutes: Int? {
        let origin = transportLeg?.origin ?? firstLeg?.origin
        guard let planned = TimeFormatting.parseTime(origin?.departureTimePlanned),
              let estimated = TimeFormatting.parseTime(origin?.departureTimeEstimated) else { return nil }
        let diff = Int(round(estimated.timeIntervalSince(planned) / 60))
        return diff > 0 ? diff : nil
    }

    private var transportMode: TransportMode? {
        guard let pc = transportLeg?.transportation?.product?.productClass else { return nil }
        return TransportMode(rawValue: pc)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(TimeFormatting.formatTime(departureTime)) \u{2192} \(TimeFormatting.formatTime(arrivalTime))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(AppColors.primaryText)

                HStack(spacing: 5) {
                    if let duration {
                        Text(duration)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    if let platform {
                        Text("\u{00b7}").foregroundStyle(AppColors.tertiaryText)
                        Text(platform)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                let countdown = TimeFormatting.formatTimeUntil(firstLeg?.origin.departureTimeEstimated ?? departureTime)
                Text(countdown)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppColors.primaryText)

                if let delay = delayMinutes {
                    Text("\(delay) min\(delay == 1 ? "" : "s") late")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                } else {
                    Text("On time")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.cardBackground)
        )
    }
}
