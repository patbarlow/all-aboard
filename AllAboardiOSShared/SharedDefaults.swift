import Foundation

enum SharedDefaults {
    static let suiteName = "group.com.patbarlow.allaboard"
    private static let tripKey = "com.allaboard.savedTrip"
    private static let journeyCacheKey = "com.allaboard.cachedJourneys"
    private static let journeyCacheDirectionKey = "com.allaboard.cachedDirection"

    static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func saveTrip(_ trip: SavedTrip?) {
        if let trip, let data = try? JSONEncoder().encode(trip) {
            suite.set(data, forKey: tripKey)
        } else {
            suite.removeObject(forKey: tripKey)
        }
    }

    static func loadTrip() -> SavedTrip? {
        guard let data = suite.data(forKey: tripKey) else { return nil }
        return try? JSONDecoder().decode(SavedTrip.self, from: data)
    }

    static func saveJourneys(_ journeys: [Journey], isAfternoonDirection: Bool) {
        if let data = try? JSONEncoder().encode(journeys) {
            suite.set(data, forKey: journeyCacheKey)
            suite.set(isAfternoonDirection, forKey: journeyCacheDirectionKey)
        }
    }

    static func loadCachedJourneys(isAfternoonDirection: Bool) -> [Journey] {
        guard suite.bool(forKey: journeyCacheDirectionKey) == isAfternoonDirection,
              let data = suite.data(forKey: journeyCacheKey) else { return [] }
        return (try? JSONDecoder().decode([Journey].self, from: data)) ?? []
    }
}
