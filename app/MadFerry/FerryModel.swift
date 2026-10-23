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
    var preferences: TripPreferences {
        didSet { preferences.save(); reloadWidgets() }
    }
    /// Direction the user picked on screen; `.auto` follows location (or the fixed preference).
    var direction: Direction = .auto

    init() {
        snapshot = FeedClient.Snapshot(schedule: FeedClient.bundledSchedule, live: nil, lastChecked: nil)
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
    var travelSeconds: TimeInterval? {
        guard let estimate, estimate.terminal == departureTerminal, estimate.isFresh(at: .now) else { return nil }
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
            refreshError = "Couldn’t reach the schedule server. Showing saved times."
        }
        await refreshTravelTime()
        reloadWidgets()
    }

    func refreshTravelTime() async {
        do {
            estimate = try await TravelEstimator.shared.estimate(preferences: preferences, schedule: snapshot.schedule)
            estimateError = nil
        } catch {
            estimateError = "Allow location access to see when to leave."
        }
    }

    // MARK: - Planning a trip

    func remind(_ plan: LeaveByPlan) async -> Bool {
        guard await LeaveByNotifier.requestAuthorization() else { return false }
        do {
            try await LeaveByNotifier.schedule(plan, alertMinutes: preferences.leaveByAlertMinutes, tz: timeZone)
        } catch {
            return false
        }
        plannedTrip = PlannedTrip.load()
        #if os(iOS)
        _ = try? FerryLiveActivity.start(plan: plan, timeZone: timeZone, disrupted: status?.disrupted ?? false)
        #endif
        reloadWidgets()
        return true
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
