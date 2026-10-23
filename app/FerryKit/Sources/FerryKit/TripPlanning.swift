import Foundation

/// User preferences shared with widgets via the App Group.
public struct TripPreferences: Codable, Sendable, Hashable {
    public enum TravelMode: String, Codable, Sendable, CaseIterable, Identifiable {
        case driving, walking
        public var id: String { rawValue }
        public var title: String { self == .driving ? "Driving (vehicle)" : "Walking / walk-on" }
    }

    /// Minutes to arrive before departure (vehicles should line up early).
    public var bufferMinutes: Int
    public var travelMode: TravelMode
    /// nil = choose automatically from location.
    public var fixedTerminal: TerminalID?
    public var leaveByAlertMinutes: Int

    public init(bufferMinutes: Int = 15, travelMode: TravelMode = .driving, fixedTerminal: TerminalID? = nil,
                leaveByAlertMinutes: Int = 10) {
        self.bufferMinutes = bufferMinutes
        self.travelMode = travelMode
        self.fixedTerminal = fixedTerminal
        self.leaveByAlertMinutes = leaveByAlertMinutes
    }

    private static let key = "tripPreferences"

    public static func load(_ defaults: UserDefaults = FerryConfig.sharedDefaults) -> TripPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(TripPreferences.self, from: data) else { return TripPreferences() }
        return prefs
    }

    public func save(_ defaults: UserDefaults = FerryConfig.sharedDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

/// Most recent travel estimate, cached so widgets can show leave-by times without running MapKit.
public struct TravelEstimate: Codable, Sendable, Hashable {
    public let terminal: TerminalID
    public let seconds: TimeInterval
    public let computedAt: Date
    public let mode: TripPreferences.TravelMode

    public init(terminal: TerminalID, seconds: TimeInterval, computedAt: Date, mode: TripPreferences.TravelMode) {
        self.terminal = terminal
        self.seconds = seconds
        self.computedAt = computedAt
        self.mode = mode
    }

    public var minutes: Int { Int((seconds / 60).rounded(.up)) }
    /// Estimates older than this are shown as stale and not used for notifications.
    public func isFresh(at now: Date) -> Bool { now.timeIntervalSince(computedAt) < 45 * 60 }

    private static let key = "travelEstimate"

    public static func load(_ defaults: UserDefaults = FerryConfig.sharedDefaults) -> TravelEstimate? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder.ferry.decode(TravelEstimate.self, from: $0) }
    }

    public func save(_ defaults: UserDefaults = FerryConfig.sharedDefaults) {
        defaults.set(try? JSONEncoder.ferry.encode(self), forKey: Self.key)
    }
}

public struct LeaveByPlan: Sendable, Hashable {
    public enum Urgency: Sendable, Hashable {
        /// Plenty of time; leave at `leaveBy`.
        case relaxed
        /// Leave within the next few minutes.
        case soon
        /// Should already have left; may still make it without the buffer.
        case hurry
        /// Can't make it even if leaving now.
        case missed
    }

    public let trip: Trip
    public let travelSeconds: TimeInterval?
    public let bufferMinutes: Int
    public let leaveBy: Date
    public let urgency: Urgency

    public init(trip: Trip, travelSeconds: TimeInterval?, bufferMinutes: Int, now: Date) {
        self.trip = trip
        self.travelSeconds = travelSeconds
        self.bufferMinutes = bufferMinutes
        let travel = travelSeconds ?? 0
        leaveBy = trip.departure.addingTimeInterval(-travel - TimeInterval(bufferMinutes * 60))
        let latestPossible = trip.departure.addingTimeInterval(-travel)
        if now > latestPossible {
            urgency = .missed
        } else if now > leaveBy {
            urgency = .hurry
        } else if leaveBy.timeIntervalSince(now) <= 10 * 60 {
            urgency = .soon
        } else {
            urgency = .relaxed
        }
    }

    /// First upcoming trip the traveler can still realistically catch, plus the following one.
    public static func plans(for trips: [Trip], travelSeconds: TimeInterval?, bufferMinutes: Int,
                             now: Date) -> [LeaveByPlan] {
        trips.map { LeaveByPlan(trip: $0, travelSeconds: travelSeconds, bufferMinutes: bufferMinutes, now: now) }
            .filter { $0.urgency != .missed }
    }
}

public enum Geography {
    /// Madeline Island bounding box; La Pointe terminal sits on its west shore.
    public static func isOnMadelineIsland(latitude: Double, longitude: Double) -> Bool {
        (46.70...46.92).contains(latitude) && (-90.800 ... -90.40).contains(longitude)
    }

    /// The terminal a traveler at this position would most likely depart from.
    public static func departureTerminal(latitude: Double, longitude: Double) -> TerminalID {
        isOnMadelineIsland(latitude: latitude, longitude: longitude) ? .lapointe : .bayfield
    }
}

public extension Date {
    /// "7:30 AM" in the ferry's local time zone.
    func ferryTime(_ tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz
        return formatted(style)
    }
}
