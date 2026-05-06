import Foundation

struct StopRef: Codable, Hashable {
    let id: String
    let name: String
}

struct SavedTrip: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let origin: StopRef
    let destination: StopRef
    let createdAt: String
}
