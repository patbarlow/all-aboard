import ActivityKit
import Foundation

struct DepartureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var departures: [DepartureSummary]
        var updatedAt: Date
    }

    var originName: String
    var destinationName: String
}

struct DepartureSummary: Codable, Hashable {
    var departureTime: Date   // estimated if available, else planned
    var arrivalTime: Date?
    var platform: String?
    var line: String?
    var isDelayed: Bool
}
