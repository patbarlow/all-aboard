import Foundation

// MARK: - Stop Finder

struct StopFinderResponse: Codable {
    let locations: [StopLocation]?
}

struct StopLocation: Codable, Identifiable {
    let id: String
    let name: String
    let disassembledName: String?
    let type: String?
    let parent: StopParent?
    let productClasses: [Int]?
    let modes: [Int]?
    let matchQuality: Int?
    let isBest: Bool?
    let properties: StopProperties?

    static func == (lhs: StopLocation, rhs: StopLocation) -> Bool {
        lhs.id == rhs.id
    }
}

struct StopParent: Codable, Hashable {
    let id: String?
    let name: String?
    let type: String?
}

struct StopProperties: Codable, Hashable {
    let stopId: String?
    let mainLocality: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stopId = try container.decodeIfPresent(String.self, forKey: .stopId)
        mainLocality = try container.decodeIfPresent(String.self, forKey: .mainLocality)
    }

    enum CodingKeys: String, CodingKey {
        case stopId
        case mainLocality
    }
}

// MARK: - Trip Planning

struct TripResponse: Codable {
    let journeys: [Journey]?
}

struct Journey: Codable, Identifiable {
    let id = UUID()
    let rating: Int?
    let interchanges: Int?
    let legs: [Leg]

    enum CodingKeys: String, CodingKey {
        case rating, interchanges, legs
    }
}

struct Leg: Codable {
    let duration: Int?
    let isRealtimeControlled: Bool?
    let origin: LegLocation
    let destination: LegLocation
    let transportation: LegTransportation?
    let footPathInfo: [FootPathInfo]?
    let stopSequence: [StopSequenceItem]?
}

struct LegLocation: Codable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let type: String?
    let departureTimePlanned: String?
    let departureTimeEstimated: String?
    let arrivalTimePlanned: String?
    let arrivalTimeEstimated: String?
    let parent: StopParent?
    let properties: LegLocationProperties?
}

struct LegLocationProperties: Codable {
    let platform: String?
    let platformName: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        platformName = try container.decodeIfPresent(String.self, forKey: .platformName)
    }

    enum CodingKeys: String, CodingKey {
        case platform, platformName
    }
}

struct LegTransportation: Codable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let number: String?
    let description: String?
    let product: TransportProduct?
    let destination: TransportDestination?
}

struct TransportProduct: Codable {
    let productClass: Int
    let name: String?

    enum CodingKeys: String, CodingKey {
        case productClass = "class"
        case name
    }
}

struct TransportDestination: Codable {
    let id: String?
    let name: String?
}

struct FootPathInfo: Codable {
    let position: String?
    let duration: Int?
}

struct StopSequenceItem: Codable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let arrivalTimePlanned: String?
    let arrivalTimeEstimated: String?
    let departureTimePlanned: String?
    let departureTimeEstimated: String?
    let properties: StopSequenceProperties?
    let parent: StopParent?
}

struct StopSequenceProperties: Codable {
    let platformName: String?
}
