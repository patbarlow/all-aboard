import Foundation

enum TimeFormatting {
    private static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_AU")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_AU")
        return f
    }()

    /// Parse ISO 8601 time string to Date
    static func parseTime(_ isoString: String?) -> Date? {
        guard let isoString else { return nil }
        if let date = iso8601Full.date(from: isoString) { return date }
        if let date = iso8601.date(from: isoString) { return date }
        return localFormatter.date(from: isoString)
    }

    /// "2:35 PM"
    static func formatTime(_ isoString: String?) -> String {
        guard let date = parseTime(isoString) else { return "" }
        return timeFormatter.string(from: date)
    }

    /// "Due", "3 min", "1 hr 15 min"
    static func formatTimeUntil(_ isoString: String?) -> String {
        guard let date = parseTime(isoString) else { return "" }
        let diffMins = Int(round(date.timeIntervalSinceNow / 60))

        if diffMins <= 0 { return "Due" }
        if diffMins == 1 { return "1 min" }
        if diffMins < 60 { return "\(diffMins) min" }

        let hours = diffMins / 60
        let mins = diffMins % 60
        if mins == 0 { return hours == 1 ? "1 hr" : "\(hours) hrs" }
        return "\(hours) hr \(mins) min"
    }

    /// "45 min", "1h 30m"
    static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}
