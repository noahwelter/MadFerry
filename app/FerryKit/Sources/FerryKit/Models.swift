import Foundation

public enum TerminalID: String, Codable, Sendable, CaseIterable, Identifiable {
    case bayfield, lapointe

    public var id: String { rawValue }
    public var other: TerminalID { self == .bayfield ? .lapointe : .bayfield }
    public var shortName: String { self == .bayfield ? "Bayfield" : "La Pointe" }
    /// "To Island" / "To Bayfield", matching the official schedule wording.
    public var directionLabel: String { self == .bayfield ? "To Island" : "To Bayfield" }
}

public struct Terminal: Codable, Sendable, Hashable, Identifiable {
    public let id: TerminalID
    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double
}

public struct Departure: Codable, Sendable, Hashable {
    public let from: TerminalID
    /// Local wall-clock time "HH:mm" in the schedule's time zone.
    public let time: String
    /// ISO weekdays, Monday = 1 … Sunday = 7.
    public let days: [Int]
    public let note: String?
    public let restricted: Bool

    public init(from: TerminalID, time: String, days: [Int], note: String? = nil, restricted: Bool = false) {
        self.from = from
        self.time = time
        self.days = days
        self.note = note
        self.restricted = restricted
    }

    var minutesAfterMidnight: Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

public struct SeasonSource: Codable, Sendable, Hashable {
    public let url: URL?
    public let hash: String?
    public let onSiteNow: Bool?
}

public struct Season: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case ferry, windsled }

    public let id: String
    public let kind: Kind
    public let label: String
    public let startDate: LocalDate?
    public let endDate: LocalDate?
    public let endNote: String?
    public let notes: [String]
    public let departures: [Departure]
    public let source: SeasonSource?
}

public struct Schedule: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let timeZone: String
    public let crossingMinutes: Int
    public let terminals: [Terminal]
    public let seasons: [Season]
    public let updatedAt: Date?

    public var tz: TimeZone { TimeZone(identifier: timeZone) ?? TimeZone(identifier: "America/Chicago")! }
    public func terminal(_ id: TerminalID) -> Terminal? { terminals.first { $0.id == id } }
    public var windsled: Season? { seasons.first { $0.kind == .windsled } }
    public var ferrySeasons: [Season] {
        seasons.filter { $0.kind == .ferry && $0.startDate != nil }.sorted { $0.startDate! < $1.startDate! }
    }
}

public enum ServiceMode: String, Codable, Sendable {
    case ferry, windsled, iceRoad = "ice_road", closed, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServiceMode(rawValue: raw) ?? .unknown
    }

    public var title: String {
        switch self {
        case .ferry: "Ferry"
        case .windsled: "Windsled"
        case .iceRoad: "Ice road open"
        case .closed: "No crossings"
        case .unknown: "Check official sources"
        }
    }
}

public struct ServiceStatus: Codable, Sendable, Hashable {
    public let mode: ServiceMode
    public let disrupted: Bool
    public let message: String?
    public let source: String?

    public init(mode: ServiceMode, disrupted: Bool = false, message: String? = nil, source: String? = nil) {
        self.mode = mode
        self.disrupted = disrupted
        self.message = message
        self.source = source
    }
}

public struct Advisory: Codable, Sendable, Hashable {
    public let text: String
}

public struct LiveFeed: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let status: ServiceStatus
    public let advisories: [Advisory]
    public let alertsUrl: URL?
    public let textAlerts: String?
    public let windsledHotline: String?
}

/// A calendar date without time ("YYYY-MM-DD").
public struct LocalDate: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ string: String) {
        let p = string.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        self.init(year: p[0], month: p[1], day: p[2])
    }

    public init(_ date: Date, in tz: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = LocalDate(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public func date(hour: Int = 0, minute: Int = 0, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    public func adding(days: Int) -> LocalDate {
        let utc = TimeZone(identifier: "UTC")!
        return LocalDate(date(hour: 12, in: utc).addingTimeInterval(TimeInterval(days * 86_400)), in: utc)
    }

    /// ISO weekday, Monday = 1 … Sunday = 7.
    public var isoWeekday: Int {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let w = cal.component(.weekday, from: date(hour: 12, in: utc)) // Sunday = 1
        return (w + 5) % 7 + 1
    }
}

extension JSONDecoder {
    public static var ferry: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    public static var ferry: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
