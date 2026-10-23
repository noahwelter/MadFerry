import Foundation
import Testing
@testable import FerryKit

private let tz = TimeZone(identifier: "America/Chicago")!

private func date(_ s: String, _ h: Int, _ m: Int) -> Date { LocalDate(s)!.date(hour: h, minute: m, in: tz) }

private let schedule = FeedClient.bundledSchedule

@Suite struct FeedSnapshotTests {
    @Test func freshnessRequiresBothFeedsAndUsesTheOlderCheck() {
        let scheduleChecked = date("2026-11-03", 10, 0)
        let liveChecked = date("2026-11-03", 9, 0)
        let snapshot = FeedClient.Snapshot(schedule: schedule, live: nil,
                                           scheduleLastChecked: scheduleChecked,
                                           liveLastChecked: liveChecked)
        #expect(snapshot.lastChecked == liveChecked)

        let incomplete = FeedClient.Snapshot(schedule: schedule, live: nil,
                                             scheduleLastChecked: scheduleChecked,
                                             liveLastChecked: nil)
        #expect(incomplete.lastChecked == nil)
    }
}

@Suite struct ScheduleEngineTests {
    let engine = ScheduleEngine(schedule: schedule)

    @Test func localDateRejectsInvalidOrNonCanonicalDates() {
        for value in ["2026-2-03", "2026-02-30", "2026-13-01", "2026/02/01", "0000-01-01"] {
            #expect(LocalDate(value) == nil)
        }
        #expect(LocalDate("2026-02-28") != nil)
    }

    @Test func departureTimeRejectsOutOfRangeComponents() {
        #expect(Departure(from: .bayfield, time: "24:00", days: [1]).minutesAfterMidnight == nil)
        #expect(Departure(from: .bayfield, time: "12:60", days: [1]).minutesAfterMidnight == nil)
        #expect(Departure(from: .bayfield, time: "1:02", days: [1]).minutesAfterMidnight == nil)
        #expect(Departure(from: .bayfield, time: "12:30", days: [1]).minutesAfterMidnight == 750)
    }

    @Test func weekdayRulesApply() {
        // 2026-11-06 is a Friday, 2026-11-05 a Thursday (Nov 2 – Nov 29 season).
        let fri = engine.trips(on: LocalDate("2026-11-06")!, today: LocalDate("2026-11-06")!, from: .bayfield)
            .map(\.departure)
        let thu = engine.trips(on: LocalDate("2026-11-05")!, today: LocalDate("2026-11-05")!, from: .bayfield)
            .map(\.departure)
        #expect(fri.contains(date("2026-11-06", 20, 0)) && !fri.contains(date("2026-11-06", 17, 30)))
        #expect(thu.contains(date("2026-11-05", 17, 30)) && !thu.contains(date("2026-11-05", 20, 0)))
        let sun = engine.trips(on: LocalDate("2026-11-08")!, today: LocalDate("2026-11-08")!, from: .bayfield)
        #expect(sun.first?.departure == date("2026-11-08", 8, 0))
    }

    @Test func openEndedIceSeasonCoversWinterAndArrivalAddsCrossing() {
        let day = LocalDate("2027-01-15")!
        #expect(engine.ferrySeason(on: day)?.id == "ferry-2026-11-30")
        let trip = engine.trips(on: day, today: day, from: .lapointe).first!
        #expect(trip.arrival.timeIntervalSince(trip.departure) == 25 * 60)
    }

    @Test func unpublishedBeforeFirstSeason() {
        let day = LocalDate("2026-01-01")!
        #expect(engine.service(on: day, today: day) == .unpublished)
    }

    @Test func upcomingCrossesMidnightAndSkipsRestricted() {
        let next = engine.upcoming(from: .bayfield, after: date("2026-11-03", 21, 0), limit: 2)
        #expect(next.map(\.departure) == [date("2026-11-04", 7, 0), date("2026-11-04", 8, 0)])
    }

    @Test func liveWindsledStatusSwitchesTodayAndPersists() {
        let live = ScheduleEngine(schedule: schedule, status: ServiceStatus(mode: .windsled))
        let today = LocalDate("2027-02-01")! // Monday
        let trips = live.trips(on: today, today: today, from: .lapointe)
        #expect(trips.allSatisfy { $0.kind == .windsled })
        #expect(trips.contains { $0.restricted })
        #expect(live.trips(on: today.adding(days: 1), today: today, from: .lapointe).first?.kind == .windsled)
        #expect(ScheduleEngine(schedule: schedule, status: ServiceStatus(mode: .iceRoad))
            .service(on: today, today: today) == .iceRoad)
    }

    @Test func isoWeekdays() {
        #expect(LocalDate("2026-10-26")!.isoWeekday == 1)
        #expect(LocalDate("2026-11-01")!.isoWeekday == 7)
        #expect(LocalDate("2026-12-31")!.adding(days: 1) == LocalDate("2027-01-01")!)
    }
}

@Suite struct LeaveByTests {
    let trip = Trip(from: .bayfield, departure: date("2026-11-03", 12, 0), arrival: date("2026-11-03", 12, 25))

    @Test(arguments: [
        (date("2026-11-03", 11, 0), LeaveByPlan.Urgency.relaxed),
        (date("2026-11-03", 11, 22), .soon),
        (date("2026-11-03", 11, 35), .hurry),
        (date("2026-11-03", 11, 45), .missed),
    ])
    func urgency(now: Date, expected: LeaveByPlan.Urgency) {
        let plan = LeaveByPlan(trip: trip, travelSeconds: 20 * 60, bufferMinutes: 10, now: now)
        #expect(plan.leaveBy == date("2026-11-03", 11, 30))
        #expect(plan.urgency == expected)
    }

    @Test func firstAlertFallsBackToLeaveByOnceHeadsUpHasPassed() {
        let plan = LeaveByPlan(trip: trip, travelSeconds: 20 * 60, bufferMinutes: 10, now: date("2026-11-03", 11, 0))
        #expect(LeaveByNotifier.firstAlert(for: plan, alertMinutes: 10, now: date("2026-11-03", 11, 0)) == date("2026-11-03", 11, 20))
        #expect(LeaveByNotifier.firstAlert(for: plan, alertMinutes: 10, now: date("2026-11-03", 11, 25)) == date("2026-11-03", 11, 30))
    }

    @Test func countdownIsCoarse() {
        let now = date("2026-11-03", 11, 0)
        #expect(now.addingTimeInterval(40 * 60 - 29).ferryCountdown(from: now) == "in 40 min")
        #expect(now.addingTimeInterval(65 * 60).ferryCountdown(from: now) == "in 1 hr 5 min")
        #expect(now.addingTimeInterval(120 * 60).ferryCountdown(from: now) == "in 2 hr")
        #expect(now.ferryCountdown(from: now) == "now")
    }

    @Test func terminalFromLocation() {
        #expect(Geography.departureTerminal(latitude: 46.7779, longitude: -90.7863) == .lapointe)
        #expect(Geography.departureTerminal(latitude: 46.8119, longitude: -90.8142) == .bayfield)
        #expect(Geography.departureTerminal(latitude: 46.79, longitude: -92.10) == .bayfield) // Duluth
    }
}
