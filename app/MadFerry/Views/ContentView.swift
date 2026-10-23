import FerryKit
import SwiftUI

struct ContentView: View {
    @Environment(FerryModel.self) private var model
    @SceneStorage("selectedTab") private var tab = AppTab.next

    enum AppTab: String { case next, schedule, alerts, settings }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Next Ferry", systemImage: "ferry", value: AppTab.next) {
                NavigationStack { NextFerryView() }
            }
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack { ScheduleView() }
            }
            Tab("Advisories", systemImage: "exclamationmark.bubble", value: AppTab.alerts) {
                NavigationStack { AdvisoriesView() }
            }
            .badge(model.snapshot.live?.advisories.count ?? 0)
            #if !os(macOS)
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// Segmented "To Island / To Bayfield" control shared by screens.
struct DirectionPicker: View {
    @Environment(FerryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Direction", selection: Binding(
            get: { model.departureTerminal },
            set: { model.direction = $0 == .bayfield ? .bayfield : .lapointe }
        )) {
            ForEach(TerminalID.allCases) { terminal in
                Text(terminal.directionLabel).tag(terminal)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Shows non-routine service status (windsled, ice road, disruptions).
struct StatusBanner: View {
    let status: ServiceStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.disrupted ? "Service disruption"
                     : status.mode == .ferry ? "Ferry running on schedule" : status.mode.title)
                    .font(.headline)
                if let message = status.message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: status.disrupted ? "exclamationmark.triangle.fill" : status.mode.symbol)
                .foregroundStyle(status.disrupted ? .orange : .accentColor)
        }
        .accessibilityElement(children: .combine)
    }
}

extension ServiceStatus {
    var isNoteworthy: Bool { disrupted || mode != .ferry || message != nil }
}
