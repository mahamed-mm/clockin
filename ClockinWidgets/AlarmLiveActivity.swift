import AlarmKit
import SwiftUI
import WidgetKit

/// The end alarm while it rings, on the Lock Screen and in the Dynamic
/// Island. The system's own alert carries Stop and Start break; this says
/// what's ringing, in Clockin's colours.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ClockinAlarm>.self) { context in
            RingingAlarmView(title: context.attributes.presentation.alert.title, tint: context.attributes.tintColor)
                .activityBackgroundTint(Retro.paper)
                .activitySystemActionForegroundColor(Retro.ink)
                .widgetURL(URL(string: "clockin://focus"))
        } dynamicIsland: { context in
            let tint = context.attributes.tintColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.waves.left.and.right.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.presentation.alert.title)
                            .retroFont(.headline)
                            .lineLimit(1)
                        Text(Copy.ringing)
                            .font(.retro(.meta))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(tint)
                    .accessibilityLabel(Copy.ringing)
            } compactTrailing: {
                Text(Copy.ringing)
                    .font(.retro(.meta))
                    .foregroundStyle(tint)
            } minimal: {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(tint)
                    .accessibilityLabel(Copy.ringing)
            }
            .keylineTint(tint)
        }
    }
}

private struct RingingAlarmView: View {
    let title: LocalizedStringResource
    let tint: Color

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(Copy.ringing)
                    .retroLabel()
                Text(title)
                    .retroFont(.headline)
                    .foregroundStyle(Retro.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .accessibilityElement(children: .combine)
    }
}
