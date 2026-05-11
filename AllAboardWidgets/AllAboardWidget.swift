import WidgetKit
import SwiftUI

// MARK: - Direction helpers

func isAfternoonDirection(at date: Date = .now) -> Bool {
    Calendar.current.component(.hour, from: date) >= 12
}

private func nextFlipTime(after date: Date) -> Date {
    let cal = Calendar.current
    let hour = cal.component(.hour, from: date)
    let targetHour = hour < 12 ? 12 : 0
    // midnight wraps to next day
    var components = DateComponents(hour: targetHour, minute: 0, second: 0)
    if targetHour == 0 {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: date)!
        components = cal.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 0
        components.minute = 0
        components.second = 0
    }
    return cal.nextDate(after: date, matching: components, matchingPolicy: .strict) ?? date.addingTimeInterval(3600)
}

func departureDate(of journey: Journey) -> Date? {
    let leg = journey.legs.first
    return TimeFormatting.parseTime(leg?.origin.departureTimeEstimated ?? leg?.origin.departureTimePlanned)
}

// MARK: - Timeline Entry

struct DepartureEntry: TimelineEntry {
    let date: Date
    let trip: SavedTrip?
    let journeys: [Journey]
    let isAfternoonDirection: Bool

    var displayOriginName: String {
        isAfternoonDirection ? (trip?.destination.name ?? "–") : (trip?.origin.name ?? "–")
    }
    var displayDestinationName: String {
        isAfternoonDirection ? (trip?.origin.name ?? "–") : (trip?.destination.name ?? "–")
    }

    // Journeys that haven't fully departed relative to this entry's date
    var upcoming: [Journey] {
        journeys.filter { j in
            guard let dep = departureDate(of: j) else { return false }
            return dep >= date
        }
    }
}

// MARK: - Provider

struct AllAboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(date: .now, trip: nil, journeys: [], isAfternoonDirection: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DepartureEntry) -> Void) {
        let trip = SharedDefaults.loadTrip()
        let isAfternoon = isAfternoonDirection()
        let cached = SharedDefaults.loadCachedJourneys(isAfternoonDirection: isAfternoon)
        completion(DepartureEntry(date: .now, trip: trip, journeys: cached, isAfternoonDirection: isAfternoon))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DepartureEntry>) -> Void) {
        Task {
            let now = Date.now
            let trip = SharedDefaults.loadTrip()
            let isAfternoon = isAfternoonDirection(at: now)

            let journeys = await fetchJourneys(trip: trip, isAfternoon: isAfternoon, from: now)

            var entries: [DepartureEntry] = []

            // Initial entry showing all fetched journeys
            entries.append(DepartureEntry(date: now, trip: trip, journeys: journeys, isAfternoonDirection: isAfternoon))

            // Entry per departure so the widget ticks forward as each train departs
            for journey in journeys {
                guard let dep = departureDate(of: journey), dep > now else { continue }
                entries.append(DepartureEntry(date: dep, trip: trip, journeys: journeys, isAfternoonDirection: isAfternoon))
            }

            // Handle direction flip at noon/midnight if within next 2 hours
            let flipTime = nextFlipTime(after: now)
            if flipTime < now.addingTimeInterval(7200) {
                let flippedIsAfternoon = !isAfternoon
                let flippedJourneys = await fetchJourneys(trip: trip, isAfternoon: flippedIsAfternoon, from: flipTime)
                entries.append(DepartureEntry(date: flipTime, trip: trip, journeys: flippedJourneys, isAfternoonDirection: flippedIsAfternoon))
            }

            let policy = TimelineReloadPolicy.after(Date(timeIntervalSinceNow: 1800))
            completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: policy))
        }
    }

    private func fetchJourneys(trip: SavedTrip?, isAfternoon: Bool, from date: Date) async -> [Journey] {
        guard let trip else { return [] }
        let originId = isAfternoon ? trip.destination.id : trip.origin.id
        let destId = isAfternoon ? trip.origin.id : trip.destination.id
        if let journeys = try? await APIClient.shared.planTrip(
            originId: originId,
            destinationId: destId,
            date: date,
            isDepartureTime: true,
            maxJourneys: 8
        ) {
            SharedDefaults.saveJourneys(journeys, isAfternoonDirection: isAfternoon)
            return journeys
        }
        return SharedDefaults.loadCachedJourneys(isAfternoonDirection: isAfternoon)
    }
}

// MARK: - Widget

struct AllAboardWidget: Widget {
    let kind = "AllAboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AllAboardProvider()) { entry in
            AllAboardWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("All Aboard")
        .description("Next departures for your saved trip.")
        .supportedFamilies([
            .systemSmall, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}
