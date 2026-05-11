import SwiftUI

struct TimetableView: View {
    let trip: SavedTrip
    let onEditTrip: () -> Void

    @StateObject private var viewModel = TimetableViewModel()
    @State private var isAfternoon = isAfternoonDirection()

    private var originName: String { isAfternoon ? trip.destination.name : trip.origin.name }
    private var destName:   String { isAfternoon ? trip.origin.name      : trip.destination.name }

    var body: some View {
        Group {
            if viewModel.journeys.isEmpty && viewModel.isLoading {
                ProgressView("Loading timetable…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.journeys.isEmpty {
                ContentUnavailableView("No departures found", systemImage: "tram.fill")
            } else {
                List(Array(viewModel.journeys.enumerated()), id: \.offset) { _, journey in
                    TimetableRow(journey: journey)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                .listStyle(.plain)
                .overlay(alignment: .bottom) {
                    if viewModel.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading more…").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .navigationTitle("\(originName) → \(destName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onEditTrip() } label: { Image(systemName: "gear") }
            }
        }
        .onAppear { viewModel.load(trip: trip, isAfternoon: isAfternoon) }
        .onDisappear { viewModel.cancel() }
    }
}

// MARK: - Row

struct TimetableRow: View {
    let journey: Journey

    private var firstLeg: Leg? { journey.legs.first }
    private var lastLeg:  Leg? { journey.legs.last }

    private var depStr: String {
        TimeFormatting.formatTime(firstLeg?.origin.departureTimeEstimated ?? firstLeg?.origin.departureTimePlanned)
    }
    private var arrStr: String {
        TimeFormatting.formatTime(lastLeg?.destination.arrivalTimeEstimated ?? lastLeg?.destination.arrivalTimePlanned)
    }
    private var countdown: String? {
        guard let dep = departureDate(of: journey), dep > Date() else { return nil }
        return TimeFormatting.formatTimeUntil(
            firstLeg?.origin.departureTimeEstimated ?? firstLeg?.origin.departureTimePlanned
        )
    }
    private var platform: String? { firstLeg?.origin.properties?.platformName }
    private var line: String? {
        let t = firstLeg?.transportation
        return t?.disassembledName ?? t?.number
    }
    private var duration: String {
        let depStr = firstLeg?.origin.departureTimePlanned
        let arrStr = lastLeg?.destination.arrivalTimePlanned
        guard let dep = TimeFormatting.parseTime(depStr), let arr = TimeFormatting.parseTime(arrStr) else { return "" }
        let mins = max(0, Int(arr.timeIntervalSince(dep) / 60))
        return mins > 0 ? "\(mins) min" : ""
    }
    private var delayed: Bool { isDelayed(journey) }
    private var realtime: Bool { hasRealtimeData(journey) }
    private var isPast: Bool { departureDate(of: journey).map { $0 < Date() } ?? false }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if realtime {
                        Circle()
                            .fill(delayed ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                    }
                    Text(arrStr.isEmpty ? depStr : "\(depStr) → \(arrStr)")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isPast ? .secondary : .primary)
                }

                HStack(spacing: 4) {
                    if let line { Text(line).foregroundStyle(.secondary) }
                    let parts = [duration, platform].compactMap { v -> String? in
                        guard let v, !v.isEmpty else { return nil }; return v
                    }
                    if !parts.isEmpty {
                        if line != nil { Text("·").foregroundStyle(.tertiary) }
                        Text(parts.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            if let cd = countdown {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cd)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text(delayed ? "Delayed" : "On time")
                        .font(.caption)
                        .foregroundStyle(delayed ? .orange : .secondary)
                }
            } else if isPast {
                Text("Departed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
