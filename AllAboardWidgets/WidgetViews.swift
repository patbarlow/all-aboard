import SwiftUI
import WidgetKit

// MARK: - Entry View dispatcher

struct AllAboardWidgetEntryView: View {
    var entry: DepartureEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:       SmallWidgetView(entry: entry)
        case .systemMedium:      MediumWidgetView(entry: entry)
        case .systemLarge:       LargeWidgetView(entry: entry)
        case .accessoryCircular: CircularWidgetView(entry: entry)
        case .accessoryRectangular: RectangularWidgetView(entry: entry)
        case .accessoryInline:   InlineWidgetView(entry: entry)
        default:                 SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Helpers

private func shortName(_ name: String) -> String {
    // Strip common suffixes so names fit in tight spaces
    name
        .replacingOccurrences(of: " Station", with: "")
        .replacingOccurrences(of: " Platform", with: "")
}

private func platformLabel(_ journey: Journey?) -> String? {
    journey?.legs.first?.origin.properties?.platformName.map { "Plt \($0)" }
}

private func lineLabel(_ journey: Journey?) -> String? {
    let t = journey?.legs.first?.transportation
    return t?.disassembledName ?? t?.number
}

private func interchangeNote(_ journey: Journey?) -> String? {
    guard let journey, let n = journey.interchanges, n > 0 else { return nil }
    return n == 1 ? "1 change" : "\(n) changes"
}

// MARK: - Route header

private struct RouteHeader: View {
    let origin: String
    let destination: String
    var font: Font = .caption2

    var body: some View {
        Label {
            Text("\(shortName(origin)) → \(shortName(destination))")
                .lineLimit(1)
        } icon: {
            Image(systemName: "tram.fill")
        }
        .font(font)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Departure row

private struct DepartureRow: View {
    let journey: Journey
    var showInterchange = false

    private var depDate: Date? { departureDate(of: journey) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let dep = depDate {
                    Text(dep, style: .time)
                        .font(.subheadline.monospacedDigit())
                }
                if let line = lineLabel(journey) {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let dep = depDate {
                    Text(dep, style: .relative)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if showInterchange, let note = interchangeNote(journey) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let plt = platformLabel(journey) {
                    Text(plt)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: DepartureEntry

    private var next: Journey? { entry.upcoming.first }
    private var depDate: Date? { next.flatMap { departureDate(of: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RouteHeader(origin: entry.displayOriginName, destination: entry.displayDestinationName)

            Spacer(minLength: 0)

            if let dep = depDate {
                Text(dep, style: .relative)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text(dep, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No trains")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                if let line = lineLabel(next) {
                    Text(line).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let plt = platformLabel(next) {
                    Text(plt).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RouteHeader(origin: entry.displayOriginName, destination: entry.displayDestinationName)
            Divider()
            let rows = Array(entry.upcoming.prefix(3))
            if rows.isEmpty {
                Text("No upcoming departures").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { journey in
                    DepartureRow(journey: journey)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RouteHeader(origin: entry.displayOriginName, destination: entry.displayDestinationName, font: .caption)
            Divider()
            let rows = Array(entry.upcoming.prefix(5))
            if rows.isEmpty {
                Text("No upcoming departures").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { journey in
                    DepartureRow(journey: journey, showInterchange: true)
                    if journey.id != rows.last?.id { Divider() }
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

    private var depDate: Date? { entry.upcoming.first.flatMap { departureDate(of: $0) } }

    var body: some View {
        ZStack {
            if let dep = depDate {
                VStack(spacing: 0) {
                    Text(dep, style: .relative)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                }
            } else {
                Image(systemName: "tram.fill")
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Accessory Rectangular

struct RectangularWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(shortName(entry.displayOriginName)) → \(shortName(entry.displayDestinationName))")
                .font(.caption2)
                .lineLimit(1)
                .widgetAccentable()
            let rows = Array(entry.upcoming.prefix(2))
            if rows.isEmpty {
                Text("No trains").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(rows) { journey in
                        if let dep = departureDate(of: journey) {
                            Text(dep, style: .time)
                                .font(.caption.monospacedDigit())
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
        if let next = entry.upcoming.first, let dep = departureDate(of: next) {
            Label {
                Text("\(shortName(entry.displayOriginName)) → \(shortName(entry.displayDestinationName)) · ")
                + Text(dep, style: .relative)
            } icon: {
                Image(systemName: "tram.fill")
            }
        } else {
            Label("No trains", systemImage: "tram.fill")
        }
    }
}
