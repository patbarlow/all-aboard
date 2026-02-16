import Foundation

enum TransportMode: Int, Codable, CaseIterable {
    case train = 1
    case metro = 2
    case lightRail = 4
    case bus = 5
    case coach = 7
    case ferry = 9
    case schoolBus = 11

    static let railModes: Set<TransportMode> = [.train, .metro, .lightRail]
    static let railModeIds: Set<Int> = Set(railModes.map(\.rawValue))

    var displayName: String {
        switch self {
        case .train: "Train"
        case .metro: "Metro"
        case .lightRail: "Light Rail"
        case .bus: "Bus"
        case .coach: "Coach"
        case .ferry: "Ferry"
        case .schoolBus: "School Bus"
        }
    }

    var sfSymbol: String {
        switch self {
        case .train: "tram.fill"
        case .metro: "tram.fill"
        case .lightRail: "lightrail.fill"
        case .bus: "bus.fill"
        case .coach: "bus.fill"
        case .ferry: "ferry.fill"
        case .schoolBus: "bus.fill"
        }
    }
}
