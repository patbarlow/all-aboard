import ActivityKit
import SwiftUI
import WidgetKit

struct DepartureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .padding(16)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(context.attributes.originName) → \(context.attributes.destinationName)")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "tram.fill")
                    }
                    .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DepartureRowList(departures: context.state.departures)
                        .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                if let next = context.state.departures.first {
                    Text(next.departureTime, style: .relative)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Lock Screen

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<DepartureActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("\(context.attributes.originName) → \(context.attributes.destinationName)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: "tram.fill")
            }
            .font(.subheadline.weight(.semibold))

            Divider()

            if context.state.departures.isEmpty {
                Text("No upcoming departures")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                DepartureRowList(departures: context.state.departures)
            }
        }
    }
}

// MARK: - Shared departure rows (Lock Screen + Dynamic Island expanded)

struct DepartureRowList: View {
    let departures: [DepartureSummary]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(departures, id: \.departureTime) { dep in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dep.departureTime, style: .time)
                            .font(.callout.weight(.semibold).monospacedDigit())
                        if let platform = dep.platform {
                            Text(platform)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        // Text date style = live countdown, no timeline entries needed
                        Text(dep.departureTime, style: .relative)
                            .font(.callout.weight(.bold).monospacedDigit())
                            .foregroundStyle(dep.isDelayed ? .orange : .primary)
                        Text(dep.isDelayed ? "Delayed" : "On time")
                            .font(.caption2)
                            .foregroundStyle(dep.isDelayed ? .orange : .secondary)
                    }
                }
                if dep != departures.last { Divider() }
            }
        }
    }
}
