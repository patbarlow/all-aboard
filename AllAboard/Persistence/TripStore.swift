import Foundation
import Observation

@Observable
class TripStore {
    var savedTrips: [SavedTrip] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("All Aboard", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("saved-trips.json")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func addTrip(origin: StopRef, destination: StopRef) {
        let trip = SavedTrip(
            id: "\(origin.id)-\(destination.id)-\(Int(Date().timeIntervalSince1970 * 1000))",
            name: "\(origin.name) \u{2192} \(destination.name)",
            origin: origin,
            destination: destination,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        savedTrips.append(trip)
        save()
    }

    func removeTrip(id: String) {
        savedTrips.removeAll { $0.id == id }
        save()
    }

    func persistOrder() {
        save()
    }

    func duplicateTrip(id: String) {
        guard let original = savedTrips.first(where: { $0.id == id }) else { return }
        let newId = "\(original.origin.id)-\(original.destination.id)-\(Int(Date().timeIntervalSince1970 * 1000))"
        let copy = SavedTrip(
            id: newId,
            name: original.name,
            origin: original.origin,
            destination: original.destination,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        savedTrips.append(copy)
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            savedTrips = try JSONDecoder().decode([SavedTrip].self, from: data)
        } catch {
            print("Failed to load saved trips: \(error)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(savedTrips)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save trips: \(error)")
        }
    }
}

