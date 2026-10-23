import FerryKit
import SwiftUI

struct AdvisoriesView: View {
    @Environment(FerryModel.self) private var model

    var body: some View {
        let live = model.snapshot.live
        List {
            if let status = live?.status {
                Section("Service") { StatusBanner(status: status) }
            }

            Section("Advisories") {
                if let items = live?.advisories, !items.isEmpty {
                    ForEach(items, id: \.self) { Text($0.text) }
                } else {
                    Label("No active alerts", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Link(destination: live?.alertsUrl ?? FerryConfig.alertsURL) {
                    Label("Official advisories", systemImage: "safari")
                }
                if let sms = URL(string: "sms:715-200-9057&body=madferry") {
                    Link(destination: sms) {
                        Label("Get text alerts", systemImage: "message")
                    }
                }
                if let phone = URL(string: "tel:\(FerryConfig.ferryPhone)") {
                    Link(destination: phone) { Label("Call the ferry line", systemImage: "phone") }
                }
                if let hotline = live?.windsledHotline, let url = URL(string: "tel:\(hotline)") {
                    Link(destination: url) { Label("Windsled / ice road hotline", systemImage: "wind.snow") }
                }
            } header: {
                Text("Stay informed")
            } footer: {
                if let text = live?.textAlerts { Text(text) }
            }

            Section {
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let generated = live?.generatedAt {
                        Text("Advisories checked \(generated, style: .relative) ago.")
                    }
                    if let error = model.refreshError { Text(error) }
                }
            }
        }
        .navigationTitle("Advisories")
        .refreshable { await model.refresh() }
    }
}

struct SettingsView: View {
    @Environment(FerryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Getting there", selection: $model.preferences.travelMode) {
                    ForEach(TripPreferences.TravelMode.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Arrive \(model.preferences.bufferMinutes) min early",
                        value: $model.preferences.bufferMinutes, in: 0...60, step: 5)
                Picker("Departing from", selection: $model.preferences.fixedTerminal) {
                    Text("Automatic").tag(TerminalID?.none)
                    ForEach(TerminalID.allCases) { Text($0.shortName).tag(Optional($0)) }
                }
            } header: {
                Text("Trip")
            } footer: {
                Text("Automatic picks La Pointe when you’re on Madeline Island and Bayfield otherwise. Vehicles should arrive early to line up.")
            }

            Section("Reminders") {
                Stepper("Heads-up \(model.preferences.leaveByAlertMinutes) min before leaving",
                        value: $model.preferences.leaveByAlertMinutes, in: 0...60, step: 5)
            }

            Section {
                Link("Madeline Island Ferry Line", destination: URL(string: "https://madferry.com")!)
            } header: {
                Text("About")
            } footer: {
                Text("Not affiliated with the Madeline Island Ferry Line. Schedules are read daily from madferry.com and may contain errors; always confirm with official sources.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: model.preferences) { Task { await model.refreshTravelTime() } }
    }
}
