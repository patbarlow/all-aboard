import SwiftUI

struct LiveTripCardSnapshot {
    let tripName: String
    let route: String
    let departureISOTime: String?
    let departureDisplay: String
    let arrivalDisplay: String
    let statusText: String
    let platformText: String
    let currentStopText: String
}

struct LiveTripCardView: View {
    let snapshot: LiveTripCardSnapshot
    let onClose: () -> Void

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var currentTime = Date()

    private var timeUntilText: String {
        _ = currentTime
        return TimeFormatting.formatTimeUntil(snapshot.departureISOTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.tripName)
                        .font(.headline)
                    Text(snapshot.route)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Departs \(snapshot.departureDisplay)")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text(timeUntilText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Label(snapshot.statusText, systemImage: snapshot.statusText.contains("late") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(snapshot.statusText.contains("late") ? .red : .green)
                    .font(.system(size: 12, weight: .medium))
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(snapshot.platformText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Live trip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(snapshot.currentStopText)
                    .font(.system(size: 12, weight: .medium))
                Text("Arrives \(snapshot.arrivalDisplay)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 10)
        .onReceive(ticker) { _ in
            currentTime = Date()
        }
    }
}
