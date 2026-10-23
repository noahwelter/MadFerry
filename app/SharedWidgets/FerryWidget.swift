import AppIntents
import FerryKit
import SwiftUI
import WidgetKit

enum DirectionOption: String, AppEnum {
    case automatic, toIsland, toBayfield

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [DirectionOption: DisplayRepresentation] = [
        .automatic: "Automatic",
        .toIsland: "To Island",
        .toBayfield: "To Bayfield",
    ]
}

struct DirectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ferry Direction"
    static let description = IntentDescription("Choose which direction to show, or follow your location.")

    @Parameter(title: "Direction", default: .automatic)
    var direction: DirectionOption

    init() {}
    init(direction: DirectionOption) { self.direction = direction }
}

struct FerryEntry: TimelineEntry {
    let date: Date
    let terminal: TerminalID
    let plans: [LeaveByPlan]
    let status: ServiceStatus?
    let dayService: DayServiceSummary
    let travelMode: TripPreferences.TravelMode
    let timeZone: TimeZone
    let plannedTripID: String?
    let lastToday: Trip?

    var next: LeaveByPlan? { plans.first }
}

/// Lightweight description of why there may be no trips.
enum DayServiceSummary {
    case trips, iceRoad, closed, unpublished

    init(_ service: DayService) {
        switch service {
        case .trips: self = .trips
        case .iceRoad: self = .iceRoad
        case .closed: self = .closed
        case .unpublished: self = .unpublished
        }
    }

    var emptyTitle: String {
        switch self {
        case .trips: "No more trips today"
        case .iceRoad: "Ice road open"
        case .closed: "No crossings"
        case .unpublished: "Schedule not posted"
        }
    }

    var emptySymbol: String {
        switch self {
        case .trips: "moon.zzz"
        case .iceRoad: "car.fill"
        case .closed: "nosign"
        case .unpublished: "calendar.badge.exclamationmark"
        }
    }
}

struct FerryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FerryEntry {
        Self.entry(snapshot: .init(schedule: FeedClient.bundledSchedule, live: nil,
                                   scheduleLastChecked: nil, liveLastChecked: nil),
                   terminal: .bayfield, at: .now)
    }

    func snapshot(for configuration: DirectionIntent, in context: Context) async -> FerryEntry {
        let snapshot = await FeedClient.shared.cached()
        return Self.entry(snapshot: snapshot, terminal: terminal(configuration), at: .now)
    }

    func timeline(for configuration: DirectionIntent, in context: Context) async -> Timeline<FerryEntry> {
        var snapshot = await FeedClient.shared.cached()
        if (snapshot.lastChecked ?? .distantPast).timeIntervalSinceNow < -6 * 60 * 60,
           let fresh = try? await FeedClient.shared.refresh() {
            snapshot = fresh
        }
        let terminal = terminal(configuration)
        let now = Date.now
        let prefs = TripPreferences.load()
        let travel = Self.travelSeconds(for: terminal, now: now)

        // Refresh exactly when something visible changes: departures and leave-by moments.
        let trips = snapshot.engine.upcoming(from: terminal, after: now, limit: 16, days: 2)
        var moments = Set([now])
        for trip in trips {
            moments.insert(trip.departure)
            let plan = LeaveByPlan(trip: trip, travelSeconds: travel, bufferMinutes: prefs.bufferMinutes, now: now)
            moments.insert(plan.leaveBy)
            moments.insert(plan.leaveBy.addingTimeInterval(-10 * 60))
        }
        let horizon = now.addingTimeInterval(12 * 60 * 60)
        let dates = moments.filter { $0 >= now && $0 <= horizon }.sorted().prefix(48)
        let entries = dates.map { Self.entry(snapshot: snapshot, terminal: terminal, at: $0) }
        let reload = min(dates.last ?? horizon, now.addingTimeInterval(60 * 60))
        return Timeline(entries: entries, policy: .after(reload))
    }

    func recommendations() -> [AppIntentRecommendation<DirectionIntent>] {
        [
            AppIntentRecommendation(intent: DirectionIntent(direction: .automatic), description: "Next Ferry"),
            AppIntentRecommendation(intent: DirectionIntent(direction: .toIsland), description: "To Island"),
            AppIntentRecommendation(intent: DirectionIntent(direction: .toBayfield), description: "To Bayfield"),
        ]
    }

    private func terminal(_ configuration: DirectionIntent) -> TerminalID {
        switch configuration.direction {
        case .toIsland: return .bayfield
        case .toBayfield: return .lapointe
        case .automatic:
            return TripPreferences.load().fixedTerminal ?? TravelEstimate.load()?.terminal ?? .bayfield
        }
    }

    private static func travelSeconds(for terminal: TerminalID, now: Date) -> TimeInterval? {
        guard let estimate = TravelEstimate.load(), estimate.terminal == terminal,
              now.timeIntervalSince(estimate.computedAt) < 3 * 60 * 60 else { return nil }
        return estimate.seconds
    }

    static func entry(snapshot: FeedClient.Snapshot, terminal: TerminalID, at date: Date) -> FerryEntry {
        let engine = snapshot.engine
        let prefs = TripPreferences.load()
        let today = LocalDate(date, in: engine.timeZone)
        let plans = LeaveByPlan.plans(for: engine.upcoming(from: terminal, after: date, limit: 8),
                                      travelSeconds: travelSeconds(for: terminal, now: date),
                                      bufferMinutes: prefs.bufferMinutes, now: date)
        return FerryEntry(
            date: date, terminal: terminal, plans: plans, status: snapshot.live?.status,
            dayService: DayServiceSummary(engine.service(on: today, today: today)),
            travelMode: prefs.travelMode, timeZone: engine.timeZone,
            plannedTripID: PlannedTrip.load(now: date)?.trip.id,
            lastToday: engine.lastTrip(from: terminal, on: today, today: today))
    }
}

struct NextFerryWidget: Widget {
    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner]
        #elseif os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #endif
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextFerry", intent: DirectionIntent.self, provider: FerryProvider()) { entry in
            FerryWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Ferry")
        .description("Upcoming departures and when to leave to catch them.")
        .supportedFamilies(Self.families)
    }
}
