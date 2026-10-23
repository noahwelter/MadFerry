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
        return minutes == 0 ? "At the terminal · \(bufferMinutes) min early"
            : "\(minutes) min \(verb) · \(bufferMinutes) min early"
    }
}
