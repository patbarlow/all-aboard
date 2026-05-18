import Foundation

func isAfternoonDirection(at date: Date = .now) -> Bool {
    Calendar.current.component(.hour, from: date) >= 12
}

func departureDate(of journey: Journey) -> Date? {
    let leg = journey.legs.first
    return TimeFormatting.parseTime(leg?.origin.departureTimeEstimated ?? leg?.origin.departureTimePlanned)
}

func hasRealtimeData(_ journey: Journey) -> Bool {
    journey.legs.first?.origin.departureTimeEstimated != nil
}

func isDelayed(_ journey: Journey) -> Bool {
    guard let leg = journey.legs.first,
          let planned = TimeFormatting.parseTime(leg.origin.departureTimePlanned),
          let estimated = TimeFormatting.parseTime(leg.origin.departureTimeEstimated) else { return false }
    return estimated.timeIntervalSince(planned) > 60
}
