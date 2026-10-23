import FerryKit
import Foundation
import Observation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

@Observable
@MainActor
final class FerryModel {
    enum ReminderFailure: Equatable {
        case notificationsNotAllowed
        case scheduling(String)

        var title: String {
            switch self {
            case .notificationsNotAllowed: "Notifications Are Off"
            case .scheduling: "Couldn’t Set Reminder"
            }
        }

        var message: String {
            switch self {
            case .notificationsNotAllowed:
                "Allow notifications for Ferry to receive a reminder when it’s time to leave."
            case .scheduling(let detail):
                "The reminder could not be scheduled. \(detail)"
            }
        }
    }

    enum Direction: String, CaseIterable, Identifiable {
        case auto, bayfield, lapointe
        var id: String { rawValue }
    }

    private(set) var snapshot: FeedClient.Snapshot
    private(set) var estimate: TravelEstimate?
    private(set) var estimateError: String?
    private(set) var isRefreshing = false
    private(set) var refreshError: String?
    private(set) var plannedTrip: PlannedTrip?
    private(set) var reminderFailure: ReminderFailure?
    var preferences: TripPreferences {
        didSet { preferences.save(); reloadWidgets() }
    }
    /// Direction the user picked on screen; `.auto` follows location (or the fixed preference).
    var direction: Direction = .auto

    init() {
        snapshot = FeedClient.Snapshot(schedule: FeedClient.bundledSchedule, live: nil,
                                       scheduleLastChecked: nil, liveLastChecked: nil)
        preferences = TripPreferences.load()
        estimate = TravelEstimate.load()
        plannedTrip = PlannedTrip.load()
    }

    var engine: ScheduleEngine { snapshot.engine }
    var timeZone: TimeZone { engine.timeZone }
    var status: ServiceStatus? { snapshot.live?.status }

    /// Terminal the traveler will depart from.
    var departureTerminal: TerminalID {
        switch direction {
        case .bayfield: return .bayfield
        case .lapointe: return .lapointe
        case .auto: return preferences.fixedTerminal ?? estimate?.terminal ?? .bayfield
        }
    }

    /// Travel time applies only when it was computed for the selected terminal.
    var travelSeconds: TimeInterval? { travelSeconds(from: departureTerminal) }

    func travelSeconds(from terminal: TerminalID) -> TimeInterval? {
        guard let estimate, estimate.terminal == terminal, estimate.isFresh(at: .now) else { return nil }
        return estimate.seconds
    }

    func upcoming(limit: Int = 8, now: Date = .now) -> [Trip] {
        engine.upcoming(from: departureTerminal, after: now, limit: limit)
    }

    func plans(now: Date = .now) -> [LeaveByPlan] {
        LeaveByPlan.plans(for: upcoming(now: now), travelSeconds: travelSeconds,
                          bufferMinutes: preferences.bufferMinutes, now: now)
    }

    func lastTripToday(now: Date = .now) -> Trip? {
        let today = LocalDate(now, in: timeZone)
        return engine.lastTrip(from: departureTerminal, on: today, today: today)
    }

    // MARK: - Loading

    func start() async {
        snapshot = await FeedClient.shared.cached()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await FeedClient.shared.refresh()
            refreshError = nil
        } catch {
            snapshot = await FeedClient.shared.cached()
            refreshError = "Some data could not be refreshed. Showing the latest available schedule and advisories."
        }
        await reschedulePlannedTrip()
        startLiveActivityIfNear()
        reloadWidgets()
    }

    func refreshTravelTime(requestAuthorizationIfNeeded: Bool = false) async {
        do {
            estimate = try await TravelEstimator.shared.estimate(
                preferences: preferences, schedule: snapshot.schedule,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded)
            estimateError = nil
        } catch {
            estimateError = "Location unavailable. Check access or choose a terminal in Settings."
        }
    }

    // MARK: - Planning a trip

    func remind(_ plan: LeaveByPlan) async -> Bool {
        do {
            guard try await LeaveByNotifier.requestAuthorization() else {
                reminderFailure = .notificationsNotAllowed
                return false
            }
            try await LeaveByNotifier.schedule(plan, alertMinutes: preferences.leaveByAlertMinutes, tz: timeZone)
        } catch {
            reminderFailure = .scheduling(error.localizedDescription)
            return false
        }
        reminderFailure = nil
        plannedTrip = PlannedTrip.load()
        startLiveActivityIfNear()
        reloadWidgets()
        return true
    }

    func clearReminderFailure() {
        reminderFailure = nil
    }

    /// Keeps leave-by alerts in step with the latest travel time and settings.
    func reschedulePlannedTrip(now: Date = .now) async {
        plannedTrip = PlannedTrip.load(now: now)
        guard let planned = plannedTrip else { return }
        let plan = LeaveByPlan(trip: planned.trip, travelSeconds: travelSeconds(from: planned.trip.from),
                               bufferMinutes: preferences.bufferMinutes, now: now)
        guard plan.canRemind else { return }
        try? await LeaveByNotifier.schedule(plan, alertMinutes: preferences.leaveByAlertMinutes, tz: timeZone, now: now)
        #if os(iOS)
        await FerryLiveActivity.update(leaveBy: plan.leaveBy, travelMinutes: estimate?.minutes,
                                       disrupted: status?.disrupted ?? false)
        #endif
    }

    /// Live Activities are for the imminent trip only; later plans start one once the app is opened near departure.
    func startLiveActivityIfNear(now: Date = .now) {
        #if os(iOS)
        guard let planned = plannedTrip, !FerryLiveActivity.isRunning else { return }
        let plan = LeaveByPlan(trip: planned.trip, travelSeconds: travelSeconds(from: planned.trip.from),
                               bufferMinutes: preferences.bufferMinutes, now: now)
        guard plan.leaveBy.timeIntervalSince(now) <= 90 * 60 else { return }
        _ = try? FerryLiveActivity.start(plan: plan, timeZone: timeZone, disrupted: status?.disrupted ?? false)
        #endif
    }

    /// When the user will first be alerted for the planned trip.
    func reminderAlert(for plan: LeaveByPlan, now: Date = .now) -> Date {
        LeaveByNotifier.firstAlert(for: plan, alertMinutes: preferences.leaveByAlertMinutes, now: now)
    }

    func cancelPlan() async {
        await LeaveByNotifier.cancelAll()
        #if os(iOS)
        FerryLiveActivity.endAll()
        #endif
        plannedTrip = nil
        reloadWidgets()
    }

    func isPlanned(_ trip: Trip) -> Bool { plannedTrip?.trip.id == trip.id }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
