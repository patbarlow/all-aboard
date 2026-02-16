import Foundation
import Observation

@Observable
class TripCreationViewModel {
    enum Step {
        case origin
        case destination
    }

    var step: Step = .origin
    var searchQuery = ""
    var searchResults: [StopLocation] = []
    var isSearching = false
    var selectedOrigin: StopLocation?
    var error: String?

    private let store: TripStore
    private let apiClient = APIClient.shared
    private var searchTask: Task<Void, Never>?

    init(store: TripStore) {
        self.store = store
    }

    func search() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        guard query.count >= 2 else {
            searchResults = []
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSearching = true
            error = nil

            do {
                searchResults = try await apiClient.searchStops(query: query)
            } catch {
                self.error = error.localizedDescription
                searchResults = []
            }

            isSearching = false
        }
    }

    func selectOrigin(_ stop: StopLocation) {
        selectedOrigin = stop
        step = .destination
        searchQuery = ""
        searchResults = []
    }

    func selectDestination(_ stop: StopLocation) {
        guard let origin = selectedOrigin else { return }
        store.addTrip(
            origin: StopRef(id: origin.id, name: origin.disassembledName ?? origin.name),
            destination: StopRef(id: stop.id, name: stop.disassembledName ?? stop.name)
        )
        reset()
    }

    func goBack() {
        step = .origin
        selectedOrigin = nil
        searchQuery = ""
        searchResults = []
    }

    func reset() {
        step = .origin
        selectedOrigin = nil
        searchQuery = ""
        searchResults = []
        error = nil
    }
}
