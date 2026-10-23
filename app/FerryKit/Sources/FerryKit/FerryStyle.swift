import SwiftUI

public extension LeaveByPlan.Urgency {
    var tint: Color {
        switch self {
        case .relaxed: .green
        case .soon: .orange
        case .hurry: .red
        case .missed: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .relaxed: "checkmark.circle.fill"
        case .soon: "clock.badge.exclamationmark.fill"
        case .hurry: "exclamationmark.triangle.fill"
        case .missed: "xmark.circle.fill"
        }
    }
}

public extension ServiceMode {
    var symbol: String {
        switch self {
        case .ferry: "ferry.fill"
        case .windsled: "wind.snow"
        case .iceRoad: "car.fill"
        case .closed: "nosign"
        case .unknown: "questionmark.circle"
        }
    }
}

public extension TerminalID {
    /// Symbol for the destination of a trip departing this terminal.
    var directionSymbol: String { self == .bayfield ? "arrow.right.circle.fill" : "arrow.left.circle.fill" }
}

public extension LeaveByPlan {
    /// "Leave by 11:32 AM", or a more urgent phrasing.
    func headline(_ tz: TimeZone) -> String {
        switch urgency {
        case .relaxed, .soon: "Leave by \(leaveBy.ferryTime(tz))"
        case .hurry: "Leave now"
        case .missed: "Too late to make it"
        }
    }

    /// "18 min drive + 15 min early" or "Arrive 15 min early".
    func detail(mode: TripPreferences.TravelMode) -> String {
        let verb = mode == .driving ? "drive" : "walk"
        guard let travelSeconds else { return "Arrive \(bufferMinutes) min early" }
        let minutes = Int((travelSeconds / 60).rounded(.up))
        guard minutes > 0 else { return "At the terminal · \(bufferMinutes) min early" }
        let travel = minutes < 60 ? "\(minutes) min"
            : minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
        return "\(travel) \(verb) · \(bufferMinutes) min early"
    }
}

public extension LeaveByPlan {
    /// A reminder only makes sense while there is still time before leave-by.
    var canRemind: Bool { urgency == .relaxed || urgency == .soon }
}

public extension Date {
    /// Coarse, glanceable countdown such as "in 40 min" or "in 1 hr 5 min".
    func ferryCountdown(from now: Date) -> String {
        let minutes = Int((timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        guard minutes >= 60 else { return "in \(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "in \(minutes / 60) hr" : "in \(minutes / 60) hr \(rest) min"
    }
}

/// Self-updating, minute-granularity countdown ("in 40 min") that works in widgets and Live Activities.
public struct CountdownText: View {
    let date: Date

    public init(to date: Date) { self.date = date }

    public var body: some View {
        Text(.currentDate, format: .reference(to: date, allowedFields: [.hour, .minute]))
    }
}
