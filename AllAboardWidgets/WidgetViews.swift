import SwiftUI
import WidgetKit

// MARK: - Entry View dispatcher

struct AllAboardWidgetEntryView: View {
    var entry: DepartureEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:          SmallWidgetView(entry: entry)
        case .systemLarge:          LargeWidgetView(entry: entry)
        case .accessoryCircular:    CircularWidgetView(entry: entry)
        case .accessoryRectangular: RectangularWidgetView(entry: entry)
        case .accessoryInline:      InlineWidgetView(entry: entry)
        default:                    SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Data helpers

private func shortName(_ name: String) -> String {
    name.replacingOccurrences(of: " Station", with: "")
}

private func shortPlatform(_ name: String) -> String {
    "PF \(name.replacingOccurrences(of: "Platform ", with: "").trimmingCharacters(in: .whitespaces))"
}

private func depTimeStr(_ journey: Journey) -> String {
    let leg = journey.legs.first
    return TimeFormatting.formatTime(leg?.origin.departureTimeEstimated ?? leg?.origin.departureTimePlanned)
}

private func arrTimeStr(_ journey: Journey) -> String {
    let leg = journey.legs.last
    return TimeFormatting.formatTime(leg?.destination.arrivalTimeEstimated ?? leg?.destination.arrivalTimePlanned)
}

private func minutesUntil(_ journey: Journey, from date: Date) -> String {
    let leg = journey.legs.first
    let str = leg?.origin.departureTimeEstimated ?? leg?.origin.departureTimePlanned
    guard let dep = TimeFormatting.parseTime(str) else { return "" }
    let mins = max(0, Int(dep.timeIntervalSince(date) / 60))
    if mins == 0 { return "Due" }
    if mins < 60 { return "\(mins) min" }
    let h = mins / 60, m = mins % 60
    return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
}

private func journeyDuration(_ journey: Journey) -> String {
    let depStr = journey.legs.first?.origin.departureTimeEstimated ?? journey.legs.first?.origin.departureTimePlanned
    let arrStr = journey.legs.last?.destination.arrivalTimeEstimated ?? journey.legs.last?.destination.arrivalTimePlanned
    guard let dep = TimeFormatting.parseTime(depStr), let arr = TimeFormatting.parseTime(arrStr) else { return "" }
    let mins = max(0, Int(arr.timeIntervalSince(dep) / 60))
    return mins > 0 ? "\(mins) min" : ""
}

private func platformName(_ journey: Journey) -> String? {
    journey.legs.first?.origin.properties?.platformName
}

private func lineLabel(_ journey: Journey) -> String? {
    let t = journey.legs.first?.transportation
    return t?.disassembledName ?? t?.number
}

private func statusLabel(_ journey: Journey) -> (text: String, delayed: Bool) {
    let leg = journey.legs.first
    guard let planned = TimeFormatting.parseTime(leg?.origin.departureTimePlanned),
          let estimated = TimeFormatting.parseTime(leg?.origin.departureTimeEstimated) else {
        return ("On time", false)
    }
    let late = Int(estimated.timeIntervalSince(planned) / 60)
    if late <= 1 { return ("On time", false) }
    return ("\(late) min late", true)
}

// MARK: - Shared subviews

private struct RouteHeader: View {
    let origin: String
    let destination: String
    var font: Font = .headline

    var body: some View {
        Text("\(shortName(origin)) → \(shortName(destination))")
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// One departure row styled like the macOS menu bar:
//   6:35 pm → 6:42 pm        9 min
//   7 min · Platform 1        On time
private struct DepartureRow: View {
    let journey: Journey
    let entryDate: Date

    var body: some View {
        let dep = depTimeStr(journey)
        let arr = arrTimeStr(journey)
        let mins = minutesUntil(journey, from: entryDate)
        let dur = journeyDuration(journey)
        let plt = platformName(journey)
        let status = statusLabel(journey)

        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(arr.isEmpty ? dep : "\(dep) → \(arr)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                subtitleText(dur: dur, plt: plt)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(mins)
                    .font(.callout.weight(.bold).monospacedDigit())
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.delayed ? Color.orange : Color.secondary)
            }
        }
    }

    @ViewBuilder
    private func subtitleText(dur: String, plt: String?) -> some View {
        let parts = [dur, plt].compactMap { $0.flatMap { $0.isEmpty ? nil : $0 } }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: DepartureEntry

    private var next: Journey? { entry.upcoming.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(origin: entry.displayOriginName, destination: entry.displayDestinationName, font: .caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            if let j = next {
                let mins = minutesUntil(j, from: entry.date)
                let dep = depTimeStr(j)
                let arr = arrTimeStr(j)

                Text(mins)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text(arr.isEmpty ? dep : "\(dep) → \(arr)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("No trains")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                if let line = next.flatMap(lineLabel) {
                    Text(line).foregroundStyle(.secondary)
                }
                if let plt = next.flatMap(platformName) {
                    Text("·").foregroundStyle(.tertiary)
                    Text(plt).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteHeader(origin: entry.displayOriginName, destination: entry.displayDestinationName)
            Divider().padding(.vertical, 8)

            let rows = Array(entry.upcoming.prefix(5))
            if rows.isEmpty {
                Text("No upcoming departures")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, journey in
                        DepartureRow(journey: journey, entryDate: entry.date)
                        if idx < rows.count - 1 { Divider() }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Accessory Circular

struct CircularWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        if let next = entry.upcoming.first {
            let mins = minutesUntil(next, from: entry.date)
            let plt = platformName(next).map { shortPlatform($0) }
            VStack(spacing: 0) {
                Text("Next")
                    .font(.system(size: 9, weight: .medium))
                Text(mins)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                if let plt {
                    Text(plt)
                        .font(.system(size: 9, weight: .medium))
                        .minimumScaleFactor(0.7)
                }
            }
            .widgetAccentable()
        } else {
            VStack(spacing: 2) {
                Image(systemName: "tram.fill")
                Text("—").font(.system(size: 12, weight: .bold))
            }
            .widgetAccentable()
        }
    }
}

// MARK: - Accessory Rectangular

struct RectangularWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(shortName(entry.displayOriginName)) → \(shortName(entry.displayDestinationName))")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()
            let rows = Array(entry.upcoming.prefix(2))
            if rows.isEmpty {
                Text("No trains").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, journey in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(depTimeStr(journey))
                                .font(.caption.monospacedDigit().weight(.semibold))
                            Text(minutesUntil(journey, from: entry.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Accessory Inline

struct InlineWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        if let next = entry.upcoming.first {
            let mins = minutesUntil(next, from: entry.date)
            let plt = platformName(next).map { shortPlatform($0) }
            let label = [mins, plt].compactMap { $0 }.joined(separator: " · ")
            Label(label, systemImage: "tram.fill")
        } else {
            Label("No trains", systemImage: "tram.fill")
        }
    }
}
