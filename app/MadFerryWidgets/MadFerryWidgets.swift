import FerryKit
import SwiftUI
import WidgetKit

@main
struct MadFerryWidgets: WidgetBundle {
    var body: some Widget {
        NextFerryWidget()
        #if os(iOS)
        FerryLiveActivityWidget()
        #endif
    }
}

#if os(iOS)
import ActivityKit

struct FerryLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FerryActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .padding()
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let tz = context.attributes.timeZone
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.from.directionLabel, systemImage: "ferry.fill")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.departure.ferryTime(tz))
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CountdownLine(context: context)
                }
            } compactLeading: {
                Image(systemName: "ferry.fill").foregroundStyle(.tint)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(context.state.leaveBy, .now), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "ferry.fill").foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<FerryActivityAttributes>

    var body: some View {
        let tz = context.attributes.timeZone
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.from.directionLabel, systemImage: "ferry.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Departs \(context.attributes.departure.ferryTime(tz))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            CountdownLine(context: context)
            if context.state.disrupted {
                Label("Check advisories — service disruption", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct CountdownLine: View {
    let context: ActivityViewContext<FerryActivityAttributes>

    var body: some View {
        let tz = context.attributes.timeZone
        let leaveBy = context.state.leaveBy
        HStack(alignment: .firstTextBaseline) {
            if leaveBy > .now {
                VStack(alignment: .leading) {
                    Text("Leave in").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...leaveBy, countsDown: true)
                        .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                }
            } else {
                VStack(alignment: .leading) {
                    Text("Departs in").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date.now...max(context.attributes.departure, .now), countsDown: true)
                        .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Leave by \(leaveBy.ferryTime(tz))").font(.subheadline.weight(.semibold))
                if let minutes = context.state.travelMinutes {
                    Text("\(minutes) min trip to the dock").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif
