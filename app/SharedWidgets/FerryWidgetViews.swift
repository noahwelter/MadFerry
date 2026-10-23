import FerryKit
import SwiftUI
import WidgetKit

struct FerryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FerryEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: InlineView(entry: entry)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        #if os(watchOS)
        case .accessoryCorner: CornerView(entry: entry)
        #endif
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: - Building blocks

private struct DirectionHeader: View {
    let entry: FerryEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.status?.mode == .windsled ? "wind.snow" : "ferry.fill")
            Text(entry.terminal.directionLabel)
            if entry.status?.disrupted == true {
                Spacer(minLength: 0)
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .accessibilityLabel("Service disruption")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct LeaveByLine: View {
    let plan: LeaveByPlan
    let entry: FerryEntry

    var body: some View {
        Label {
            Text(plan.headline(entry.timeZone)).lineLimit(1).minimumScaleFactor(0.8)
        } icon: {
            Image(systemName: plan.urgency.symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(plan.urgency.tint)
        .widgetAccentable()
    }
}

private struct EmptyStateView: View {
    let entry: FerryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.dayService.emptySymbol).font(.title2)
            Text(entry.dayService.emptyTitle).font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct HeroView: View {
    let plan: LeaveByPlan
    let entry: FerryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.trip.departure.ferryTime(entry.timeZone))
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            CountdownText(to: plan.trip.departure)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Home screen

private struct SmallView: View {
    let entry: FerryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DirectionHeader(entry: entry)
            if let plan = entry.next {
                HeroView(plan: plan, entry: entry)
                Spacer(minLength: 0)
                LeaveByLine(plan: plan, entry: entry)
                if let after = entry.plans.dropFirst().first {
                    Text("Then \(after.trip.departure.ferryTime(entry.timeZone))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                EmptyStateView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumView: View {
    let entry: FerryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SmallView(entry: entry)
            if entry.plans.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Later").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(entry.plans.dropFirst().prefix(4), id: \.trip.id) { plan in
                        CompactRow(plan: plan, entry: entry)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LargeView: View {
    let entry: FerryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectionHeader(entry: entry)
            if let plan = entry.next {
                HStack(alignment: .bottom) {
                    HeroView(plan: plan, entry: entry)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        LeaveByLine(plan: plan, entry: entry)
                        Text(plan.detail(mode: entry.travelMode))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(entry.plans.dropFirst().prefix(6), id: \.trip.id) { plan in
                    CompactRow(plan: plan, entry: entry)
                }
                Spacer(minLength: 0)
                footer
            } else {
                EmptyStateView(entry: entry)
                footer
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let message = entry.status?.message {
            Label(message, systemImage: "exclamationmark.bubble")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        } else if let last = entry.lastToday, last.departure > entry.date {
            Label("Last today \(last.departure.ferryTime(entry.timeZone))", systemImage: "moon.stars")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CompactRow: View {
    let plan: LeaveByPlan
    let entry: FerryEntry

    var body: some View {
        HStack {
            Text(plan.trip.departure.ferryTime(entry.timeZone))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if entry.plannedTripID == plan.trip.id {
                Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.tint)
            }
            Spacer(minLength: 4)
            Text("leave \(plan.leaveBy.ferryTime(entry.timeZone))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

// MARK: - Accessory (Lock Screen, watch complications)

private struct RectangularView: View {
    let entry: FerryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(entry.terminal.directionLabel, systemImage: "ferry.fill")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let plan = entry.next {
                Text(plan.trip.departure.ferryTime(entry.timeZone))
                    .font(.headline.monospacedDigit())
                Text(plan.headline(entry.timeZone)).font(.caption2)
            } else {
                Text(entry.dayService.emptyTitle).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let entry: FerryEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "ferry.fill").font(.caption2).widgetAccentable()
                if let plan = entry.next {
                    Text(plan.trip.departure, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .environment(\.timeZone, entry.timeZone)
                } else {
                    Text("—")
                }
            }
        }
    }
}

private struct InlineView: View {
    let entry: FerryEntry

    var body: some View {
        if let plan = entry.next {
            Label("\(plan.trip.departure.ferryTime(entry.timeZone)) · \(plan.headline(entry.timeZone))",
                  systemImage: "ferry.fill")
        } else {
            Label(entry.dayService.emptyTitle, systemImage: "ferry")
        }
    }
}

#if os(watchOS)
private struct CornerView: View {
    let entry: FerryEntry

    var body: some View {
        Image(systemName: "ferry.fill")
            .widgetLabel {
                if let plan = entry.next {
                    Text(plan.trip.departure.ferryTime(entry.timeZone))
                } else {
                    Text("No ferry")
                }
            }
    }
}
#endif
