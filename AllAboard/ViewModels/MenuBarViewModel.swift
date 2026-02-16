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
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        hasStarted = false
    }

    @MainActor
    func refresh() async {
        let displayTrips = Array(store.savedTrips.prefix(3))
        guard !displayTrips.isEmpty else {
            tripsWithJourneys = []
            return
        }

        isLoading = true
        var results: [TripWithJourneys] = []

        // Load sequentially to avoid rate limits
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
}
