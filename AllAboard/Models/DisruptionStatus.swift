import Foundation

enum JourneyRealtimeStatus {
    case onTime
    case delayed(minutes: Int)
    case cancelled
    /// The API returned a planned time but no realtime estimate for this leg —
    /// distinct from `.onTime`, since we genuinely don't know whether it's running to schedule.
    case realtimeUnavailable
    /// Planned time itself couldn't be parsed — malformed/missing data.
    case unknown

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

extension Journey {
    /// Best-effort realtime status for the journey's first transport leg.
    /// Delay detection (via planned vs. estimated departure) is solid — it's documented
    /// TfNSW behaviour. Cancellation detection relies on an undocumented field
    /// (`RealtimeTripStatus`) and hasn't yet been confirmed against a live cancellation.
    var realtimeStatus: JourneyRealtimeStatus {
        let firstLeg = legs.first
        let transportLeg = legs.first { $0.transportation != nil }
        let originLoc = transportLeg?.origin ?? firstLeg?.origin

        if let statuses = originLoc?.properties?.realtimeTripStatus,
           statuses.contains(where: { $0.uppercased().contains("CANCEL") }) {
            return .cancelled
        }

        guard let planned = TimeFormatting.parseTime(originLoc?.departureTimePlanned) else {
            return .unknown
        }
        guard let estimated = TimeFormatting.parseTime(originLoc?.departureTimeEstimated) else {
            return .realtimeUnavailable
        }

        let diffMins = Int(round(estimated.timeIntervalSince(planned) / 60))
        return diffMins <= 0 ? .onTime : .delayed(minutes: diffMins)
    }

    /// Whether the journey's first departure has already happened (with a small grace window).
    var isPast: Bool {
        let firstLeg = legs.first
        let transportLeg = legs.first { $0.transportation != nil }
        let originLoc = transportLeg?.origin ?? firstLeg?.origin
        guard let dep = TimeFormatting.parseTime(originLoc?.departureTimeEstimated ?? originLoc?.departureTimePlanned) else {
            return false
        }
        return dep.timeIntervalSinceNow < -60
    }
}

enum LineDisruptionLevel: Equatable {
    case normal
    case disrupted(reason: String)

    var isDisrupted: Bool {
        if case .disrupted = self { return true }
        return false
    }
}

extension TripWithJourneys {
    /// A trip is flagged as disrupted when there are two or more meaningfully-late
    /// (>5 min) upcoming departures, or two or more cancellations — a single late or
    /// cancelled train in isolation is normal day-to-day variance and isn't flagged.
    var disruptionLevel: LineDisruptionLevel {
        let statuses = journeys.prefix(5).map(\.realtimeStatus)

        let delayedCount = statuses.filter {
            if case .delayed(let minutes) = $0 { return minutes > 5 }
            return false
        }.count

        let cancelledCount = statuses.filter {
            if case .cancelled = $0 { return true }
            return false
        }.count

        if cancelledCount >= 2 {
            return .disrupted(reason: "\(cancelledCount) cancellations on this line")
        }
        if delayedCount >= 2 {
            return .disrupted(reason: "Multiple delayed services")
        }
        if cancelledCount >= 1 && delayedCount >= 1 {
            return .disrupted(reason: "Delays and a cancellation")
        }
        return .normal
    }
}

extension Array where Element == TripWithJourneys {
    var hasAnyDisruption: Bool {
        contains { $0.disruptionLevel.isDisrupted }
    }
}
