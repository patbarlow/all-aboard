import Foundation
import Observation

struct TripWithJourneys: Identifiable {
    let id: String
    let name: String
    let origin: StopRef
    let destination: StopRef
    var journeys: [Journey]
    var error: String?
}

/// Determines whether the commute trip should automatically show the return
/// direction (e.g. home from work) in the afternoon, without touching the
/// persisted saved-trip direction.
enum TripDirectionFlip {
    static func isAutoFlipActive(cutoffHour: Int = 12, now: Date = Date()) -> Bool {
        Calendar.current.component(.hour, from: now) >= cutoffHour
    }
}

func flippedDirection(origin: StopRef, destination: StopRef) -> (origin: StopRef, destination: StopRef, name: String) {
    (destination, origin, "\(destination.name) \u{2192} \(origin.name)")
}

@Observable
class MenuBarViewModel {
    var tripsWithJourneys: [TripWithJourneys] = []
    var isLoading = false
    var lastUpdated: Date?

    private let store: TripStore
    private let apiClient = APIClient.shared
    private var refreshTask: Task<Void, Never>?
    private var hasStarted = false
    private var tickCount = 0

    init(store: TripStore) {
        self.store = store
    }

    func startAutoRefreshIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        startAutoRefresh()
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            // Initial full refresh
            await self?.refresh(flipFirstTrip: TripDirectionFlip.isAutoFlipActive())

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { break }

                self.tickCount += 1
                let flipFirstTrip = TripDirectionFlip.isAutoFlipActive()

                if self.tickCount % 2 == 0 {
                    // Every 60s: refresh all trips
                    await self.refresh(flipFirstTrip: flipFirstTrip)
                } else {
                    // Every 30s: refresh just the first trip
                    await self.refreshFirstTrip(flipped: flipFirstTrip)
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        hasStarted = false
    }

    /// Refresh all trips (up to 3)
    /// - Parameter flipFirstTrip: When true, the first saved trip is queried and displayed
    ///   in the reverse direction (used for the automatic afternoon commute-home flip).
    @MainActor
    func refresh(flipFirstTrip: Bool = false) async {
        let displayTrips = Array(store.savedTrips.prefix(3))
        guard !displayTrips.isEmpty else {
            tripsWithJourneys = []
            return
        }

        isLoading = true
        var results: [TripWithJourneys] = []

        for (index, trip) in displayTrips.enumerated() {
            var origin = trip.origin
            var destination = trip.destination
            var name = trip.name
            if index == 0 && flipFirstTrip {
                (origin, destination, name) = flippedDirection(origin: origin, destination: destination)
            }

            do {
                let journeys = try await apiClient.planTrip(
                    originId: origin.id,
                    destinationId: destination.id
                )
                results.append(TripWithJourneys(
                    id: trip.id,
                    name: name,
                    origin: origin,
                    destination: destination,
                    journeys: Array(journeys.prefix(5))
                ))
            } catch {
                results.append(TripWithJourneys(
                    id: trip.id,
                    name: name,
                    origin: origin,
                    destination: destination,
                    journeys: [],
                    error: error.localizedDescription
                ))
            }
        }

        tripsWithJourneys = results
        lastUpdated = Date()
        isLoading = false
    }

    /// Refresh only the first trip (for the menu bar countdown)
    @MainActor
    func refreshFirstTrip(flipped: Bool = false) async {
        guard let firstSaved = store.savedTrips.first else { return }

        var origin = firstSaved.origin
        var destination = firstSaved.destination
        var name = firstSaved.name
        if flipped {
            (origin, destination, name) = flippedDirection(origin: origin, destination: destination)
        }

        do {
            let journeys = try await apiClient.planTrip(
                originId: origin.id,
                destinationId: destination.id
            )
            let updated = TripWithJourneys(
                id: firstSaved.id,
                name: name,
                origin: origin,
                destination: destination,
                journeys: Array(journeys.prefix(5))
            )

            if let idx = tripsWithJourneys.firstIndex(where: { $0.id == firstSaved.id }) {
                tripsWithJourneys[idx] = updated
            } else {
                tripsWithJourneys.insert(updated, at: 0)
            }
            lastUpdated = Date()
        } catch {
            // Keep existing data on error
        }
    }
}
