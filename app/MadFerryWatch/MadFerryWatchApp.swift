import FerryKit
import SwiftUI

@main
struct MadFerryWatchApp: App {
    @State private var model = FerryModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(model)
                .task { await model.start() }
        }
    }
}

struct WatchContentView: View {
    @Environment(FerryModel.self) private var model
    @State private var reminderFailed = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let plans = model.plans(now: context.date)
                List {
                    if let status = model.status, status.disrupted || status.mode != .ferry {
                        Label(status.disrupted ? "Disruption" : status.mode.title,
                              systemImage: status.disrupted ? "exclamationmark.triangle.fill" : status.mode.symbol)
                            .foregroundStyle(status.disrupted ? .orange : .primary)
                    }
                    if let first = plans.first {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(first.trip.departure.ferryTime(model.timeZone))
                                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                Text(first.trip.departure.ferryCountdown(from: context.date))
                                    .font(.footnote).foregroundStyle(.secondary)
                                Label(first.headline(model.timeZone), systemImage: first.urgency.symbol)
                                    .font(.headline)
                                    .foregroundStyle(first.urgency.tint)
                                Text(first.detail(mode: model.preferences.travelMode))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if model.isPlanned(first.trip) {
                                Label("Reminder at \(model.reminderAlert(for: first, now: context.date).ferryTime(model.timeZone))",
                                      systemImage: "bell.badge.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.tint)
                                Button("Turn Off Reminder", systemImage: "bell.slash", role: .destructive) {
                                    Task { await model.cancelPlan() }
                                }
                            } else if first.canRemind {
                                Button("Remind Me to Leave", systemImage: "bell") {
                                    Task {
                                        if !(await model.remind(first)) { reminderFailed = true }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        Section("Later") {
                            ForEach(plans.dropFirst().prefix(6), id: \.trip.id) { plan in
                                HStack {
                                    Text(plan.trip.departure.ferryTime(model.timeZone)).monospacedDigit()
                                    Spacer()
                                    Text("leave \(plan.leaveBy.ferryTime(model.timeZone))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("No departures soon", systemImage: "ferry")
                    }
                }
            }
            .navigationTitle(model.departureTerminal.directionLabel)
            .alert(model.reminderFailure?.title ?? "Reminder Failed", isPresented: $reminderFailed) {
                Button("OK", role: .cancel) { model.clearReminderFailure() }
            } message: {
                Text(model.reminderFailure?.message ?? "Please try again.")
            }
            .sensoryFeedback(.success, trigger: model.plannedTrip) { old, new in new != nil && old != new }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Switch direction", systemImage: "arrow.left.arrow.right") {
                        model.direction = model.departureTerminal == .bayfield ? .lapointe : .bayfield
                    }
                }
            }
        }
    }
}
