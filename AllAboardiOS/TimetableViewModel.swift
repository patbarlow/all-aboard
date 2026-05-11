import Foundation
import SwiftUI

@MainActor
final class TimetableViewModel: ObservableObject {
    @Published var journeys: [Journey] = []
    @Published var isLoading = false

    private var loadTask: Task<Void, Never>?

    func load(trip: SavedTrip, isAfternoon: Bool) {
        loadTask?.cancel()
        journeys = []
        isLoading = true

        loadTask = Task {
            var results: [Journey] = []
            var fromDate = Date()
            let cutoff = Date().addingTimeInterval(24 * 3600)
            let originId = isAfternoon ? trip.destination.id : trip.origin.id
            let destId   = isAfternoon ? trip.origin.id      : trip.destination.id

            while !Task.isCancelled && fromDate < cutoff {
                guard let batch = try? await APIClient.shared.planTrip(
                    originId: originId,
                    destinationId: destId,
                    date: fromDate,
                    isDepartureTime: true,
                    maxJourneys: 6
                ), !batch.isEmpty else { break }

                // Deduplicate by planned departure time
                let seen = Set(results.compactMap { $0.legs.first?.origin.departureTimePlanned })
                let fresh = batch.filter {
                    guard let t = $0.legs.first?.origin.departureTimePlanned else { return true }
                    return !seen.contains(t)
                }
                guard !fresh.isEmpty else { break }
                results.append(contentsOf: fresh)

                // Publish incrementally so the list fills in as batches arrive
                self.journeys = results

                // Advance past the last departure in this batch
                if let last = batch.last, let dep = departureDate(of: last) {
                    fromDate = dep.addingTimeInterval(60)
                } else {
                    break
                }
            }

            self.journeys = results
            self.isLoading = false
        }
    }

    func cancel() { loadTask?.cancel() }
}
