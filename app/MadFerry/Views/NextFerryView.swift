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
                if let error = model.refreshError {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                    }
                }

                if let status = model.status, status.isNoteworthy {
                    Section { StatusBanner(status: status) }
                }

                Section {
                    DirectionPicker()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let planned = model.plannedTrip, planned.trip.id != plans.first?.trip.id {
                    Section("Your Trip") {
                        PlannedTripRow(trip: planned.trip, now: now) { await model.cancelPlan() }
                    }
                }

                if let first = plans.first {
                    Section {
                        NextTripCard(plan: first, now: now, planned: model.isPlanned(first.trip),
                                     remind: { await remind(first) },
                                     cancel: { await model.cancelPlan() })
                    } footer: {
                        travelFooter
                    }

                    if plans.count > 1 {
                        Section("Later") {
                            ForEach(plans.dropFirst(), id: \.trip.id) { plan in
                                TripRow(plan: plan, planned: model.isPlanned(plan.trip)) {
                                    await toggleReminder(plan)
                                }
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
            .animation(.default, value: model.plannedTrip)
        }
        .navigationTitle("Next Ferry")
        .refreshable { await model.refresh() }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isRefreshing)
                    .keyboardShortcut("r")
            }
        }
        #endif
        .sensoryFeedback(.success, trigger: model.plannedTrip) { old, new in new != nil && old != new }
        .alert(model.reminderFailure?.title ?? "Reminder Failed", isPresented: $reminderFailed) {
            if model.reminderFailure == .notificationsNotAllowed {
                #if os(iOS)
                Button("Open Settings") {
                    model.clearReminderFailure()
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                #endif
            }
            Button("OK", role: .cancel) { model.clearReminderFailure() }
        } message: {
            Text(model.reminderFailure?.message ?? "Please try again.")
        }
    }

    @ViewBuilder private var travelFooter: some View {
        if let error = model.estimateError {
            VStack(alignment: .leading, spacing: 4) {
                Label(error, systemImage: "location.slash")
                estimateButton
            }
        } else if model.travelSeconds != nil {
            Text("Includes current \(model.preferences.travelMode == .driving ? "driving" : "walking") time from your location.")
        } else if model.estimate != nil {
            VStack(alignment: .leading, spacing: 4) {
                Label("Travel estimate is stale. Leave-by times assume you’re nearby.",
                      systemImage: "location.slash")
                estimateButton
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Travel time unavailable. Leave-by times assume you’re nearby.")
                estimateButton
            }
        }
    }

    private var estimateButton: some View {
        Button("Estimate travel time from your location", systemImage: "location") {
            Task {
                await model.refreshTravelTime(requestAuthorizationIfNeeded: true)
                await model.reschedulePlannedTrip()
            }
        }
        .font(.footnote)
    }

    @ViewBuilder private func reminderButton(_ plan: LeaveByPlan) -> some View {
        if model.isPlanned(plan.trip) {
            Button("Turn Off Reminder", systemImage: "bell.slash") { Task { await model.cancelPlan() } }
        } else if plan.canRemind {
            Button("Remind Me to Leave", systemImage: "bell") { Task { await remind(plan) } }
        }
    }

    private func remind(_ plan: LeaveByPlan) async {
        if !(await model.remind(plan)) { reminderFailed = true }
    }

    private func toggleReminder(_ plan: LeaveByPlan) async {
        if model.isPlanned(plan.trip) {
            await model.cancelPlan()
        } else {
            await remind(plan)
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
    let remind: () async -> Void
    let cancel: () async -> Void

    var body: some View {
        let tz = model.timeZone
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.trip.kind == .windsled ? "Next windsled" : "Next ferry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(plan.trip.departure.ferryCountdown(from: now))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
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

            reminderControl
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var reminderControl: some View {
        if planned {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminder On").font(.subheadline.weight(.semibold))
                        Text("Alert at \(model.reminderAlert(for: plan, now: now).ferryTime(model.timeZone))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.tint)
                        .symbolEffect(.bounce, value: planned)
                }
                Spacer(minLength: 0)
                Button("Turn Off") { Task { await cancel() } }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Turn off reminder")
            }
            .transition(.opacity)
        } else if plan.canRemind {
            Button {
                Task { await remind() }
            } label: {
                // Explicit icon color: List rows otherwise tint label icons with the accent color,
                // which disappears against the prominent (accent) button background.
                Label("Remind Me to Leave", systemImage: "bell.fill")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .transition(.opacity)
        }
    }
}

/// The trip the user has a reminder for, when it isn't the next departure.
struct PlannedTripRow: View {
    @Environment(FerryModel.self) private var model
    let trip: Trip
    let now: Date
    let cancel: () async -> Void

    var body: some View {
        let plan = LeaveByPlan(trip: trip, travelSeconds: model.travelSeconds(from: trip.from),
                               bufferMinutes: model.preferences.bufferMinutes, now: now)
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(trip.departure.ferryTime(model.timeZone)) to \(trip.to.shortName)")
                        .font(.headline.monospacedDigit())
                    Text(plan.headline(model.timeZone))
                        .font(.subheadline)
                        .foregroundStyle(plan.urgency == .relaxed ? .secondary : plan.urgency.tint)
                    if plan.canRemind {
                        Text("Reminder at \(model.reminderAlert(for: plan, now: now).ferryTime(model.timeZone))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "bell.badge.fill").foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
            Button("Turn Off") { Task { await cancel() } }
                .buttonStyle(.glass)
                .accessibilityLabel("Turn off reminder")
        }
    }
}

struct TripRow: View {
    @Environment(FerryModel.self) private var model
    let plan: LeaveByPlan
    let planned: Bool
    let toggleReminder: () async -> Void

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
            Text(plan.headline(tz))
                .font(.subheadline)
                .foregroundStyle(plan.urgency == .relaxed ? .secondary : plan.urgency.tint)
            if planned || plan.canRemind {
                Button {
                    Task { await toggleReminder() }
                } label: {
                    Image(systemName: planned ? "bell.fill" : "bell")
                        .foregroundStyle(planned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(planned ? "Turn off reminder" : "Remind me to leave")
            }
        }
    }
}
