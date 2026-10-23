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
                                Text(first.trip.departure, style: .relative)
                                    .font(.footnote).foregroundStyle(.secondary)
                                Label(first.headline(model.timeZone), systemImage: first.urgency.symbol)
                                    .font(.headline)
                                    .foregroundStyle(first.urgency.tint)
                                Text(first.detail(mode: model.preferences.travelMode))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button(model.isPlanned(first.trip) ? "Cancel Reminder" : "Remind Me",
                                   systemImage: model.isPlanned(first.trip) ? "bell.slash" : "bell") {
                                Task {
                                    if model.isPlanned(first.trip) { await model.cancelPlan() }
                                    else { _ = await model.remind(first) }
                                }
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
