import FerryKit
import SwiftUI

struct ScheduleView: View {
    @Environment(FerryModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var day = Date.now

    var body: some View {
        let tz = model.timeZone
        let today = LocalDate(.now, in: tz)
        let selected = LocalDate(day, in: tz)
        let service = model.engine.service(on: selected, today: today)

        List {
            Section {
                DatePicker("Date", selection: $day, displayedComponents: .date)
                if sizeClass == .compact {
                    DirectionPicker()
                }
            }

            switch service {
            case .trips(let season, let trips):
                if sizeClass == .compact {
                    departures(trips.filter { $0.from == model.departureTerminal }, title: nil)
                } else {
                    Section {
                        HStack(alignment: .top, spacing: 24) {
                            ForEach(TerminalID.allCases) { terminal in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(terminal.directionLabel).font(.headline)
                                    ForEach(trips.filter { $0.from == terminal }) { trip in
                                        TripTimeRow(trip: trip)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                seasonFooter(season)
            case .iceRoad:
                ContentUnavailableView("Ice road open", systemImage: "car.fill",
                                       description: Text("No ferry or windsled schedule applies."))
            case .closed:
                ContentUnavailableView("No crossings", systemImage: "nosign")
            case .unpublished:
                ContentUnavailableView {
                    Label("Not yet published", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("The ferry line hasn’t posted a schedule for \(day.formatted(date: .abbreviated, time: .omitted)).")
                } actions: {
                    Link("Official Schedule", destination: FerryConfig.officialScheduleURL)
                }
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Today", systemImage: "calendar.badge.clock") { day = .now }
                    .disabled(selected == today)
            }
        }
    }

    private func departures(_ trips: [Trip], title: String?) -> some View {
        Section {
            if trips.isEmpty {
                Text("No departures").foregroundStyle(.secondary)
            }
            ForEach(trips) { TripTimeRow(trip: $0) }
        }
    }

    private func seasonFooter(_ season: Season) -> some View {
        Section {
            if season.kind == .windsled {
                Link(destination: FerryConfig.windsledURL) {
                    Label("Windsled information", systemImage: "wind.snow")
                }
            }
            Link(destination: season.source?.url ?? FerryConfig.officialScheduleURL) {
                Label("View official schedule", systemImage: "photo")
            }
        } header: {
            Text(season.label)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let end = season.endNote {
                    Text(end)
                }
                ForEach(season.notes, id: \.self) { Text($0) }
                Text("Unofficial app. Times can change; confirm with the Madeline Island Ferry Line.")
            }
        }
    }
}

struct TripTimeRow: View {
    @Environment(FerryModel.self) private var model
    let trip: Trip

    var body: some View {
        let past = trip.departure < .now
        HStack(alignment: .firstTextBaseline) {
            Text(trip.departure.ferryTime(model.timeZone))
                .font(.body.monospacedDigit().weight(.medium))
            if trip.restricted {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Restricted")
            }
            Spacer()
            if let note = trip.note {
                Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            } else {
                Text("arrives \(trip.arrival.ferryTime(model.timeZone))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(past ? 0.4 : 1)
    }
}
