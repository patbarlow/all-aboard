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
    var naturalLanguageQuery = ""
    var oneOffJourneys: [Journey] = []
    var oneOffOrigin: StopLocation?
    var oneOffDestination: StopLocation?
    var oneOffDescription: String?
    var isRunningNaturalLanguageQuery = false
    var naturalLanguageError: String?

    private let store: TripStore
    private let apiClient = APIClient.shared
    private var searchTask: Task<Void, Never>?
    private var naturalLanguageTask: Task<Void, Never>?

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

    func runNaturalLanguageQuery() {
        naturalLanguageTask?.cancel()
        let prompt = naturalLanguageQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prompt.isEmpty else {
            naturalLanguageError = "Enter a query like: trains from Central to Redfern after 5pm"
            oneOffJourneys = []
            oneOffOrigin = nil
            oneOffDestination = nil
            oneOffDescription = nil
            return
        }

        let parsed = NaturalLanguageTripQueryParser.parse(prompt)
        guard let originName = parsed.origin, let destinationName = parsed.destination else {
            naturalLanguageError = "Couldn’t parse route. Use: from [origin] to [destination] [after/before time]"
            oneOffJourneys = []
            oneOffOrigin = nil
            oneOffDestination = nil
            oneOffDescription = nil
            return
        }

        naturalLanguageTask = Task { @MainActor in
            isRunningNaturalLanguageQuery = true
            naturalLanguageError = nil

            do {
                async let originCandidates = apiClient.searchStops(query: originName)
                async let destinationCandidates = apiClient.searchStops(query: destinationName)
                let (origins, destinations) = try await (originCandidates, destinationCandidates)

                guard let origin = bestStopMatch(for: originName, in: origins),
                      let destination = bestStopMatch(for: destinationName, in: destinations) else {
                    throw QueryError.stopNotFound
                }

                let journeys = try await apiClient.planTrip(
                    originId: origin.id,
                    destinationId: destination.id,
                    date: parsed.date,
                    isDepartureTime: parsed.timeRelation != .before
                )

                oneOffOrigin = origin
                oneOffDestination = destination
                oneOffJourneys = Array(journeys.prefix(5))
                oneOffDescription = parsed.description
                if oneOffJourneys.isEmpty {
                    naturalLanguageError = "No upcoming rail trips found."
                }
            } catch QueryError.stopNotFound {
                naturalLanguageError = "Couldn’t find one of those stations. Try using full station names."
                oneOffJourneys = []
                oneOffOrigin = nil
                oneOffDestination = nil
                oneOffDescription = nil
            } catch {
                naturalLanguageError = error.localizedDescription
                oneOffJourneys = []
                oneOffOrigin = nil
                oneOffDestination = nil
                oneOffDescription = nil
            }

            isRunningNaturalLanguageQuery = false
        }
    }

    func saveOneOffTrip() {
        guard let origin = oneOffOrigin, let destination = oneOffDestination else { return }
        store.addTrip(
            origin: StopRef(id: origin.id, name: origin.disassembledName ?? origin.name),
            destination: StopRef(id: destination.id, name: destination.disassembledName ?? destination.name)
        )
    }

    func clearOneOffResults() {
        oneOffJourneys = []
        oneOffOrigin = nil
        oneOffDestination = nil
        oneOffDescription = nil
        naturalLanguageError = nil
    }

    private enum QueryError: LocalizedError {
        case stopNotFound
    }

    private func bestStopMatch(for name: String, in candidates: [StopLocation]) -> StopLocation? {
        let normalizedQuery = normalize(name)
        return candidates.max(by: { score(candidate: $0, query: normalizedQuery) < score(candidate: $1, query: normalizedQuery) })
    }

    private func score(candidate: StopLocation, query: String) -> Int {
        let primary = normalize(candidate.disassembledName ?? candidate.name)
        var score = candidate.matchQuality ?? 0
        if primary == query { score += 10_000 }
        if primary.contains(query) || query.contains(primary) { score += 2_000 }
        if let locality = candidate.properties?.mainLocality, normalize(locality).contains(query) {
            score += 500
        }
        return score
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " station", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NaturalLanguageTripQuery {
    enum TimeRelation {
        case after
        case before
        case none
    }

    let origin: String?
    let destination: String?
    let date: Date
    let timeRelation: TimeRelation
    let description: String
}

private enum NaturalLanguageTripQueryParser {
    static func parse(_ input: String) -> NaturalLanguageTripQuery {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let lower = normalized.lowercased()
        let routeRegex = try? NSRegularExpression(
            pattern: #"(?:from\s+)(.+?)(?:\s+to\s+)(.+?)(?=(?:\s+(?:after|before)\b)|$)"#,
            options: []
        )

        var origin: String?
        var destination: String?
        if let routeRegex, let match = routeRegex.firstMatch(
            in: lower,
            range: NSRange(location: 0, length: lower.utf16.count)
        ) {
            origin = extractGroup(1, from: match, in: normalized)
            destination = extractGroup(2, from: match, in: normalized)
        }

        let current = Date()
        let parsedTime = parseTime(from: lower, referenceDate: current)
        let relation: NaturalLanguageTripQuery.TimeRelation
        if lower.contains("before ") {
            relation = .before
        } else if lower.contains("after ") {
            relation = .after
        } else {
            relation = .none
        }

        let description = [
            relation == .before ? "Arrive by" : "Depart after",
            formattedTime(parsedTime),
        ].joined(separator: " ")

        return NaturalLanguageTripQuery(
            origin: origin,
            destination: destination,
            date: parsedTime,
            timeRelation: relation,
            description: description
        )
    }

    private static func parseTime(from lower: String, referenceDate: Date) -> Date {
        let regex = try? NSRegularExpression(
            pattern: #"(?:after|before)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#,
            options: []
        )

        var date = referenceDate
        if lower.contains("tomorrow"), let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) {
            date = tomorrow
        }

        guard let regex,
              let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)) else {
            return date
        }

        let hourString = extractGroup(1, from: match, in: lower) ?? "0"
        let minuteString = extractGroup(2, from: match, in: lower) ?? "0"
        let meridiem = extractGroup(3, from: match, in: lower)

        var hour = Int(hourString) ?? 0
        let minute = Int(minuteString) ?? 0
        if let meridiem {
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))
        return Calendar.current.date(from: components) ?? referenceDate
    }

    private static func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func extractGroup(_ group: Int, from match: NSTextCheckingResult, in text: String) -> String? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
