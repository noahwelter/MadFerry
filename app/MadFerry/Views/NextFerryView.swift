import FerryKit
import SwiftUI

struct NextFerryView: View {
    @Environment(FerryModel.self) private var model
    @State private var reminderFailed = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let plans = model.plans(now: now)
            List {
                if let status = model.status, status.isNoteworthy {
                    Section { StatusBanner(status: status) }
                }

                Section {
                    DirectionPicker()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let first = plans.first {
                    Section {
                        NextTripCard(plan: first, now: now, planned: model.isPlanned(first.trip)) {
                            await toggleReminder(first)
                        }
                    } footer: {
                        travelFooter
                    }

                    if plans.count > 1 {
                        Section("Later") {
                            ForEach(plans.dropFirst(), id: \.trip.id) { plan in
                                TripRow(plan: plan, planned: model.isPlanned(plan.trip))
                                    .contextMenu { reminderButton(plan) }
                                    .swipeActions { reminderButton(plan).tint(.accentColor) }
                            }
                        }
                    }
                } else {
                    Section { emptyState(now: now) }
                }

                if let last = model.lastTripToday(now: now), last.departure > now {
                    Section {
                        Label("Last ferry \(model.departureTerminal.directionLabel.lowercased()) today: \(last.departure.ferryTime(model.timeZone))",
                              systemImage: "moon.stars")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.default, value: plans.map(\.trip.id))
        }
        .navigationTitle(model.departureTerminal.directionLabel)
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isRefreshing)
            }
        }
        .alert("Couldn’t set a reminder", isPresented: $reminderFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow notifications for Madeline Ferry in Settings.")
        }
    }

    @ViewBuilder private var travelFooter: some View {
        if let error = model.estimateError {
            Label(error, systemImage: "location.slash")
        } else if let estimate = model.estimate, estimate.terminal == model.departureTerminal {
            Text("Travel time from your location, updated \(estimate.computedAt, style: .relative) ago.")
        }
    }

    @ViewBuilder private func reminderButton(_ plan: LeaveByPlan) -> some View {
        if model.isPlanned(plan.trip) {
            Button("Cancel Reminder", systemImage: "bell.slash") { Task { await model.cancelPlan() } }
        } else {
            Button("Remind Me to Leave", systemImage: "bell") { Task { await toggleReminder(plan) } }
        }
    }

    private func toggleReminder(_ plan: LeaveByPlan) async {
        if model.isPlanned(plan.trip) {
            await model.cancelPlan()
        } else if !(await model.remind(plan)) {
            reminderFailed = true
        }
    }

    @ViewBuilder private func emptyState(now: Date) -> some View {
        let today = LocalDate(now, in: model.timeZone)
        switch model.engine.service(on: today, today: today) {
        case .iceRoad:
            ContentUnavailableView("Ice road is open", systemImage: "car.fill",
                                   description: Text("Drive across on the ice road. Check conditions before you go."))
        case .closed:
            ContentUnavailableView("No crossings right now", systemImage: "nosign",
                                   description: Text("See Advisories for the latest information."))
        case .unpublished:
            ContentUnavailableView("Schedule not yet published", systemImage: "calendar.badge.exclamationmark",
                                   description: Text("The ferry line hasn’t posted times for these dates yet."))
        case .trips:
            ContentUnavailableView("No more departures soon", systemImage: "moon.zzz",
                                   description: Text("Check the Schedule tab for upcoming days."))
        }
    }
}

struct NextTripCard: View {
    @Environment(FerryModel.self) private var model
    let plan: LeaveByPlan
    let now: Date
    let planned: Bool
    let toggleReminder: () async -> Void

    var body: some View {
        let tz = model.timeZone
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.trip.kind == .windsled ? "Next windsled" : "Next ferry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(plan.trip.departure, style: .relative)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(plan.trip.departure.ferryTime(tz))
                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            Text("\(plan.trip.from.shortName) → \(plan.trip.to.shortName) · arrives \(plan.trip.arrival.ferryTime(tz))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = plan.trip.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }

            Divider()

            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.headline(tz)).font(.headline)
                    Text(plan.detail(mode: model.preferences.travelMode))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: plan.urgency.symbol).foregroundStyle(plan.urgency.tint)
            }

            Button {
                Task { await toggleReminder() }
            } label: {
                Label(planned ? "Reminder Set" : "Remind Me to Leave",
                      systemImage: planned ? "bell.badge.fill" : "bell")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

struct TripRow: View {
    @Environment(FerryModel.self) private var model
    let plan: LeaveByPlan
    let planned: Bool

    var body: some View {
        let tz = model.timeZone
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.trip.departure.ferryTime(tz))
                    .font(.headline.monospacedDigit())
                if let note = plan.trip.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if planned {
                Image(systemName: "bell.fill").foregroundStyle(.tint).accessibilityLabel("Reminder set")
            }
            Text(plan.headline(tz))
                .font(.subheadline)
                .foregroundStyle(plan.urgency == .relaxed ? .secondary : plan.urgency.tint)
        }
    }
}
