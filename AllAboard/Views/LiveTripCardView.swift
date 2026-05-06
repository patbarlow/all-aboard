import SwiftUI

struct LiveTripCardSnapshot {
    let route: String
    let departureISOTime: String?
    let departureDisplay: String
    let statusText: String
    let platformText: String
    let currentStop: String
}

struct LiveTripCardView: View {
    let snapshot: LiveTripCardSnapshot
    let onClose: () -> Void

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var currentTime = Date()
    @State private var isHovered = false

    private var timeUntilText: String {
        _ = currentTime
        return TimeFormatting.formatTimeUntil(snapshot.departureISOTime)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // Route header
                Text(snapshot.route)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Divider()
                    .padding(.vertical, 1)

                // Station name + countdown
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.currentStop)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text("Departs \(snapshot.departureDisplay)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            if !snapshot.platformText.isEmpty {
                                Text("·")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Text(snapshot.platformText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !snapshot.statusText.isEmpty && snapshot.statusText != "Live" {
                            Text(snapshot.statusText)
                                .font(.system(size: 11))
                                .foregroundStyle(snapshot.statusText.contains("late") ? .red : .secondary)
                        }
                    }

                    Spacer(minLength: 12)

                    Text(timeUntilText)
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                }
            }
            .padding(12)
            .frame(width: 260)

            // Close button — visible on hover only
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(5)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .padding(7)
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AppColors.contentBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppColors.contentBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
        .onHover { isHovered = $0 }
        .onReceive(ticker) { _ in currentTime = Date() }
    }
}
