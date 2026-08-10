import Foundation

actor APIClient {
    static let shared = APIClient()

    // TODO: Replace with your deployed Cloudflare Worker URL
    private let baseURL = "https://trainboard-api.pat-barlow.workers.dev"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Stop Search

    func searchStops(query: String) async throws -> [StopLocation] {
        guard query.count >= 2 else { return [] }

        var components = URLComponents(string: "\(baseURL)/stop_finder")!
        components.queryItems = [
            URLQueryItem(name: "outputFormat", value: "rapidJSON"),
            URLQueryItem(name: "coordOutputFormat", value: "EPSG:4326"),
            URLQueryItem(name: "type_sf", value: "any"),
            URLQueryItem(name: "name_sf", value: query),
            URLQueryItem(name: "TfNSWSF", value: "true"),
            URLQueryItem(name: "anyMaxSizeHitList", value: "100"),
        ]

        let response: StopFinderResponse = try await fetch(url: components.url!)
        let railModes = TransportMode.railModeIds

        return (response.locations ?? [])
            .filter { stop in
                if let modes = stop.modes {
                    return !modes.filter({ railModes.contains($0) }).isEmpty
                }
                if let productClasses = stop.productClasses {
                    return !productClasses.filter({ railModes.contains($0) }).isEmpty
                }
                let name = stop.name.lowercased()
                return name.contains("station") || name.contains("light rail") || name.contains("metro")
            }
            .sorted { ($0.matchQuality ?? 0) > ($1.matchQuality ?? 0) }
    }

    // MARK: - Trip Planning

    func planTrip(originId: String, destinationId: String, maxJourneys: Int = 6) async throws -> [Journey] {
        try await planTrip(
            originId: originId,
            destinationId: destinationId,
            date: Date(),
            isDepartureTime: true,
            maxJourneys: maxJourneys
        )
    }

    func planTrip(
        originId: String,
        destinationId: String,
        date: Date,
        isDepartureTime: Bool,
        maxJourneys: Int = 6
    ) async throws -> [Journey] {
        let calendar = Calendar.current
        let dateStr = String(
            format: "%04d%02d%02d",
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
        let timeStr = String(
            format: "%02d%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )

        var components = URLComponents(string: "\(baseURL)/trip")!
        components.queryItems = [
            URLQueryItem(name: "outputFormat", value: "rapidJSON"),
            URLQueryItem(name: "coordOutputFormat", value: "EPSG:4326"),
            URLQueryItem(name: "depArrMacro", value: isDepartureTime ? "dep" : "arr"),
            URLQueryItem(name: "type_origin", value: "stop"),
            URLQueryItem(name: "name_origin", value: originId),
            URLQueryItem(name: "type_destination", value: "stop"),
            URLQueryItem(name: "name_destination", value: destinationId),
            URLQueryItem(name: "itdDate", value: dateStr),
            URLQueryItem(name: "itdTime", value: timeStr),
            URLQueryItem(name: "TfNSWTR", value: "true"),
            URLQueryItem(name: "exclMOT_5", value: "1"),
            URLQueryItem(name: "exclMOT_7", value: "1"),
            URLQueryItem(name: "exclMOT_9", value: "1"),
            URLQueryItem(name: "exclMOT_11", value: "1"),
            URLQueryItem(name: "calcNumberOfTrips", value: "\(maxJourneys)"),
        ]

        let response: TripResponse = try await fetch(url: components.url!)
        let railModes = TransportMode.railModeIds

        let railOnly = (response.journeys ?? [])
            .filter { journey in
                journey.legs.allSatisfy { leg in
                    guard let transport = leg.transportation else { return true }
                    guard let mode = transport.product?.productClass else { return true }
                    return railModes.contains(mode)
                }
            }

        return Self.droppingSlowOutliers(railOnly)
            .sorted { a, b in
                let aTime = a.legs.first?.origin.departureTimePlanned ?? ""
                let bTime = b.legs.first?.origin.departureTimePlanned ?? ""
                return aTime < bTime
            }
    }

    /// Drops journeys that take much longer than the fastest option in the same batch —
    /// e.g. a route via an unusual interchange when a direct line covers the same trip
    /// in a third of the time. Never drops below a single result.
    private static func droppingSlowOutliers(_ journeys: [Journey], tolerance: Double = 1.5) -> [Journey] {
        guard journeys.count > 1 else { return journeys }

        func totalDuration(_ journey: Journey) -> Int {
            var total = 0
            for leg in journey.legs { total += leg.duration ?? 0 }
            return total
        }

        let positiveDurations = journeys.map(totalDuration).filter { $0 > 0 }
        guard let minDuration = positiveDurations.min() else { return journeys }
        let maxAllowed = Double(minDuration) * tolerance

        let filtered = journeys.filter { journey in
            let duration = totalDuration(journey)
            return duration <= 0 || Double(duration) <= maxAllowed
        }

        return filtered.isEmpty ? journeys : filtered
    }

    // MARK: - Private

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        if let token = AuthManager.shared.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200: break
        case 401: throw APIError.notSignedIn
        case 403: throw APIError.licenseRequired
        default: throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case notSignedIn
    case licenseRequired
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .notSignedIn: return "Please sign in to continue."
        case .licenseRequired: return "A license is required. Tap Buy in Settings."
        case .httpError(let code): return "Server error (\(code))"
        }
    }
}
