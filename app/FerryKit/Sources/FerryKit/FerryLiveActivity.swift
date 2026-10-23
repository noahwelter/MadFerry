#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity / Dynamic Island countdown to a chosen departure.
public struct FerryActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var leaveBy: Date
        public var travelMinutes: Int?
        public var disrupted: Bool

        public init(leaveBy: Date, travelMinutes: Int?, disrupted: Bool) {
            self.leaveBy = leaveBy
            self.travelMinutes = travelMinutes
            self.disrupted = disrupted
        }
    }

    public var from: TerminalID
    public var departure: Date
    public var arrival: Date
    public var timeZoneID: String

    public init(trip: Trip, timeZone: TimeZone) {
        from = trip.from
        departure = trip.departure
        arrival = trip.arrival
        timeZoneID = timeZone.identifier
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

public enum FerryLiveActivity {
    @discardableResult
    public static func start(plan: LeaveByPlan, timeZone: TimeZone, disrupted: Bool) throws -> Activity<FerryActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        endAll()
        let state = FerryActivityAttributes.ContentState(
            leaveBy: plan.leaveBy, travelMinutes: plan.travelSeconds.map { Int(($0 / 60).rounded(.up)) },
            disrupted: disrupted)
        return try Activity.request(
            attributes: FerryActivityAttributes(trip: plan.trip, timeZone: timeZone),
            content: .init(state: state, staleDate: plan.trip.departure.addingTimeInterval(5 * 60)))
    }

    public static func update(leaveBy: Date, travelMinutes: Int?, disrupted: Bool) async {
        let state = FerryActivityAttributes.ContentState(leaveBy: leaveBy, travelMinutes: travelMinutes, disrupted: disrupted)
        for activity in Activity<FerryActivityAttributes>.activities {
            await activity.update(.init(state: state, staleDate: activity.attributes.departure.addingTimeInterval(5 * 60)))
        }
    }

    public static func endAll() {
        let ids = Set(Activity<FerryActivityAttributes>.activities.map(\.id))
        Task {
            for activity in Activity<FerryActivityAttributes>.activities where ids.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    public static var isRunning: Bool { !Activity<FerryActivityAttributes>.activities.isEmpty }
}
#endif
