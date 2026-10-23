import FerryKit
import SwiftUI

@main
struct MadFerryApp: App {
    @State private var model = FerryModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                    #if os(iOS)
                    if phase == .background { BackgroundRefresh.schedule() }
                    #endif
                }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 460)
        }
        #endif
    }
}

#if os(iOS)
import BackgroundTasks
import WidgetKit

enum BackgroundRefresh {
    static let identifier = "com.noahwelter.madferry.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(3 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Refresh the feed and travel time so widgets and the Live Activity stay accurate.
    static func run() async {
        schedule()
        let snapshot = try? await FeedClient.shared.refresh()
        let prefs = TripPreferences.load()
        if let snapshot, let planned = PlannedTrip.load() {
            let estimate = try? await TravelEstimator.shared.estimate(preferences: prefs, schedule: snapshot.schedule)
            let plan = LeaveByPlan(trip: planned.trip, travelSeconds: estimate?.seconds,
                                   bufferMinutes: prefs.bufferMinutes, now: .now)
            await FerryLiveActivity.update(leaveBy: plan.leaveBy, travelMinutes: estimate?.minutes,
                                           disrupted: snapshot.live?.status.disrupted ?? false)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
