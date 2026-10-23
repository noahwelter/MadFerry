import Foundation

/// A concrete crossing on a specific date.
public struct Trip: Codable, Sendable, Hashable, Identifiable {
    public let from: TerminalID
    public let departure: Date
    public let arrival: Date
    public let note: String?
    public let restricted: Bool
    public let kind: Season.Kind

    public var id: String { "\(from.rawValue)-\(Int(departure.timeIntervalSince1970))" }
    public var to: TerminalID { from.other }

    public init(from: TerminalID, departure: Date, arrival: Date, note: String? = nil,
                restricted: Bool = false, kind: Season.Kind = .ferry) {
        self.from = from
        self.departure = departure
        self.arrival = arrival
        self.note = note
        self.restricted = restricted
        self.kind = kind
    }
}

/// What the schedule says about a given day.
public enum DayService: Sendable, Equatable {
    case trips(season: Season, trips: [Trip])
    case iceRoad
    case closed
    /// No published schedule covers this date (yet).
    case unpublished
}

public struct ScheduleEngine: Sendable {
    public let schedule: Schedule
    public let status: ServiceStatus?

    public init(schedule: Schedule, status: ServiceStatus? = nil) {
        self.schedule = schedule
        self.status = status
    }

    public var timeZone: TimeZone { schedule.tz }

    /// Ferry season covering `day`. Open-ended seasons ("until heavy ice") run until the next season starts.
    public func ferrySeason(on day: LocalDate) -> Season? {
        let seasons = schedule.ferrySeasons
        for (i, season) in seasons.enumerated() {
            guard let start = season.startDate, start <= day else { continue }
            var end = season.endDate
            if end == nil, i + 1 < seasons.count, let next = seasons[i + 1].startDate {
                end = next.adding(days: -1)
            }
            if end == nil || day <= end! { return season }
        }
        return nil
    }

    /// Live status only describes today; future days fall back to the published ferry schedule,
    /// except that windsled/ice-road status persists while no newer ferry season has started.
    public func service(on day: LocalDate, today: LocalDate) -> DayService {
        let season = ferrySeason(on: day)
        let mode = status?.mode ?? .ferry
        let liveApplies = day == today || (mode != .ferry && season == ferrySeason(on: today))
        if liveApplies {
            switch mode {
            case .windsled:
                if let w = schedule.windsled { return .trips(season: w, trips: trips(for: w, on: day)) }
            case .iceRoad: return .iceRoad
            case .closed: return .closed
            case .ferry, .unknown: break
            }
        }
        guard let season else { return .unpublished }
        return .trips(season: season, trips: trips(for: season, on: day))
    }

    public func trips(for season: Season, on day: LocalDate) -> [Trip] {
        let weekday = day.isoWeekday
        let crossing = TimeInterval(schedule.crossingMinutes * 60)
        return season.departures
            .filter { $0.days.contains(weekday) }
            .compactMap { dep -> Trip? in
                guard let m = dep.minutesAfterMidnight else { return nil }
                let start = day.date(hour: m / 60, minute: m % 60, in: timeZone)
                return Trip(from: dep.from, departure: start, arrival: start.addingTimeInterval(crossing),
                            note: dep.note, restricted: dep.restricted, kind: season.kind)
            }
            .sorted { $0.departure < $1.departure }
    }

    public func trips(on day: LocalDate, today: LocalDate, from terminal: TerminalID? = nil) -> [Trip] {
        guard case .trips(_, let all) = service(on: day, today: today) else { return [] }
        return terminal.map { t in all.filter { $0.from == t } } ?? all
    }

    /// Public departures after `now`, looking ahead up to `days` days.
    public func upcoming(from terminal: TerminalID, after now: Date, limit: Int = 5, days: Int = 7) -> [Trip] {
        let today = LocalDate(now, in: timeZone)
        var out: [Trip] = []
        for offset in 0...days {
            let day = today.adding(days: offset)
            out += trips(on: day, today: today, from: terminal).filter { $0.departure > now && !$0.restricted }
            if out.count >= limit { break }
        }
        return Array(out.prefix(limit))
    }

    /// The last public departure of the day from `terminal`, if any remain.
    public func lastTrip(from terminal: TerminalID, on day: LocalDate, today: LocalDate) -> Trip? {
        trips(on: day, today: today, from: terminal).last { !$0.restricted }
    }
}
