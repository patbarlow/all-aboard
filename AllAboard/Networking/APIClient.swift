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

        return (response.journeys ?? [])
            .filter { journey in
                journey.legs.allSatisfy { leg in
                    guard let transport = leg.transportation else { return true }
                    guard let mode = transport.product?.productClass else { return true }
                    return railModes.contains(mode)
                }
            }
            .sorted { a, b in
                let aTime = a.legs.first?.origin.departureTimePlanned ?? ""
                let bTime = b.legs.first?.origin.departureTimePlanned ?? ""
                return aTime < bTime
            }
    }

    // MARK: - Private

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from server"
        case .httpError(let code): "Server error (\(code))"
        }
    }
}
