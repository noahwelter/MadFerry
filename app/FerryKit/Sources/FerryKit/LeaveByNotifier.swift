import Foundation
import UserNotifications

/// Local "time to leave" notifications for a chosen departure.
public enum LeaveByNotifier {
    private static let prefix = "leaveBy."

    public static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// When the first reminder for `plan` will fire: the heads-up if it's still ahead, otherwise leave-by.
    public static func firstAlert(for plan: LeaveByPlan, alertMinutes: Int, now: Date = .now) -> Date {
        let headsUp = plan.leaveBy.addingTimeInterval(-TimeInterval(alertMinutes * 60))
        return headsUp > now ? headsUp : plan.leaveBy
    }

    /// Schedules a heads-up `alertMinutes` before leave-by and an alert at leave-by. Replaces any previous plan.
    public static func schedule(_ plan: LeaveByPlan, alertMinutes: Int, tz: TimeZone, now: Date = .now) async throws {
        await cancelAll()
        let center = UNUserNotificationCenter.current()
        let to = plan.trip.to.shortName
        let departs = plan.trip.departure.ferryTime(tz)
        let reminders: [(Date, String, String)] = [
            (plan.leaveBy.addingTimeInterval(-TimeInterval(alertMinutes * 60)), "Leave in \(alertMinutes) min",
             "Head out by \(plan.leaveBy.ferryTime(tz)) for the \(departs) ferry to \(to)."),
            (plan.leaveBy, "Time to leave", "Leave now to catch the \(departs) ferry to \(to)."),
        ]
        for (index, reminder) in reminders.enumerated() where reminder.0 > now {
            let content = UNMutableNotificationContent()
            content.title = reminder.1
            content.body = reminder.2
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "leaveBy"
            content.userInfo = ["tripID": plan.trip.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reminder.0.timeIntervalSince(now), repeats: false)
            try await center.add(UNNotificationRequest(identifier: "\(prefix)\(index)", content: content, trigger: trigger))
        }
        PlannedTrip(trip: plan.trip).save()
    }

    public static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        PlannedTrip.clear()
    }
}

/// The departure the user has chosen to catch (shared with widgets and the watch).
public struct PlannedTrip: Codable, Sendable, Hashable {
    public let trip: Trip
    private static let key = "plannedTrip"

    public init(trip: Trip) { self.trip = trip }

    public static func load(_ defaults: UserDefaults = FerryConfig.sharedDefaults, now: Date = .now) -> PlannedTrip? {
        guard let data = defaults.data(forKey: key),
              let planned = try? JSONDecoder.ferry.decode(PlannedTrip.self, from: data),
              planned.trip.departure > now else { return nil }
        return planned
    }

    public func save(_ defaults: UserDefaults = FerryConfig.sharedDefaults) {
        defaults.set(try? JSONEncoder.ferry.encode(self), forKey: Self.key)
    }

    public static func clear(_ defaults: UserDefaults = FerryConfig.sharedDefaults) {
        defaults.removeObject(forKey: key)
    }
}
