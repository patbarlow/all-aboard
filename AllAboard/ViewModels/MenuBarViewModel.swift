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
            await self?.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { break }

                self.tickCount += 1

                if self.tickCount % 2 == 0 {
                    // Every 60s: refresh all trips
                    await self.refresh()
                } else {
                    // Every 30s: refresh just the first trip
                    await self.refreshFirstTrip()
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
    @MainActor
    func refresh() async {
        let displayTrips = Array(store.savedTrips.prefix(3))
        guard !displayTrips.isEmpty else {
            tripsWithJourneys = []
            return
        }

        isLoading = true
        var results: [TripWithJourneys] = []

        for trip in displayTrips {
            do {
                let journeys = try await apiClient.planTrip(
                    originId: trip.origin.id,
                    destinationId: trip.destination.id
                )
                results.append(TripWithJourneys(
                    id: trip.id,
                    name: trip.name,
                    origin: trip.origin,
                    destination: trip.destination,
                    journeys: Array(journeys.prefix(5))
                ))
            } catch {
                results.append(TripWithJourneys(
                    id: trip.id,
                    name: trip.name,
                    origin: trip.origin,
                    destination: trip.destination,
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
    func refreshFirstTrip() async {
        guard let firstSaved = store.savedTrips.first else { return }

        do {
            let journeys = try await apiClient.planTrip(
                originId: firstSaved.origin.id,
                destinationId: firstSaved.destination.id
            )
            let updated = TripWithJourneys(
                id: firstSaved.id,
                name: firstSaved.name,
                origin: firstSaved.origin,
                destination: firstSaved.destination,
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
