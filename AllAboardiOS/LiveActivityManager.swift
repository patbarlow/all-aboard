import ActivityKit
import Foundation

final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var currentActivity: Activity<DepartureActivityAttributes>?
    private var refreshTask: Task<Void, Never>?

    func start() async {
        await end()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let trip = SharedDefaults.loadTrip() else { return }

        let isAfternoon = isAfternoonDirection()
        let originName = isAfternoon ? trip.destination.name : trip.origin.name
        let destName   = isAfternoon ? trip.origin.name      : trip.destination.name
        let originId   = isAfternoon ? trip.destination.id   : trip.origin.id
        let destId     = isAfternoon ? trip.origin.id        : trip.destination.id

        let journeys = (try? await APIClient.shared.planTrip(
            originId: originId, destinationId: destId, maxJourneys: 5
        )) ?? []

        let attributes = DepartureActivityAttributes(originName: originName, destinationName: destName)
        let content = ActivityContent(
            state: makeState(from: journeys),
            staleDate: Date().addingTimeInterval(120)
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            scheduleRefresh(originId: originId, destId: destId)
        } catch {
            print("Live Activity failed to start: \(error)")
        }
    }

    func end() async {
        refreshTask?.cancel()
        refreshTask = nil
        await currentActivity?.end(dismissalPolicy: .immediate)
        currentActivity = nil
    }

    private func scheduleRefresh(originId: String, destId: String) {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }

                let journeys = (try? await APIClient.shared.planTrip(
                    originId: originId, destinationId: destId, maxJourneys: 5
                )) ?? []

                let content = ActivityContent(
                    state: makeState(from: journeys),
                    staleDate: Date().addingTimeInterval(120)
                )
                await currentActivity?.update(content)
            }
        }
    }

    private func makeState(from journeys: [Journey]) -> DepartureActivityAttributes.ContentState {
        let now = Date()
        let summaries: [DepartureSummary] = journeys
            .filter { (departureDate(of: $0) ?? .distantPast) >= now }
            .prefix(3)
            .compactMap { journey in
                guard let dep = departureDate(of: journey) else { return nil }
                let arr = TimeFormatting.parseTime(
                    journey.legs.last?.destination.arrivalTimeEstimated ??
                    journey.legs.last?.destination.arrivalTimePlanned
                )
                return DepartureSummary(
                    departureTime: dep,
                    arrivalTime: arr,
                    platform: journey.legs.first?.origin.properties?.platformName,
                    line: journey.legs.first?.transportation?.disassembledName ??
                          journey.legs.first?.transportation?.number,
                    isDelayed: isDelayed(journey)
                )
            }
        return DepartureActivityAttributes.ContentState(departures: summaries, updatedAt: now)
    }
}
