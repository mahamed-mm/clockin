import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenFocusView(context: context)
                .activityBackgroundTint(Retro.paper)
                .activitySystemActionForegroundColor(Retro.ink)
                .widgetURL(URL(string: "clockin://focus"))
        } dynamicIsland: { context in
            let state = context.state
            let tint = Retro.tint(for: state.phase)
            let done = isDone(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.phase.label, systemImage: state.phase.symbol)
                        .font(.retro(.label))
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !done { PauseResumeButton(isPaused: state.isPaused, tint: tint) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.sessionName)
                        .font(.retro(.headline))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        FocusCountdown(reading: TimerReading(state: state, done: done))
                            .font(.retroDisplay(size: 40))
                            .multilineTextAlignment(.center)
                        ProgressBar(state: state, done: done, tint: tint)
                        if let ends = endsLine(state, done: done) {
                            Text(ends).font(.retro(.meta)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: state.phase.symbol)
                    .foregroundStyle(tint)
            } compactTrailing: {
                FocusCountdown(reading: TimerReading(state: state, done: done))
                    .font(.system(.body, design: .serif).weight(.black))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 52)
                    .foregroundStyle(tint)
            } minimal: {
                if let end = state.endDate, !done {
                    ProgressView(timerInterval: state.timerRange, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: state.phase.symbol).font(.caption2)
                    }
                    .progressViewStyle(.circular)
                    .tint(tint)
                    .id(end)
                } else {
                    Image(systemName: done ? "checkmark" : "pause.fill").foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
            .widgetURL(URL(string: "clockin://focus"))
        }
    }
}

private func isDone(_ context: ActivityViewContext<FocusActivityAttributes>) -> Bool {
    if context.isStale { return true }
    if let end = context.state.endDate { return end <= .now }
    return false
}

/// "Ends 14:30" while running; nothing when paused or done.
private func endsLine(_ state: FocusActivityAttributes.ContentState, done: Bool) -> String? {
    guard !done, let end = state.endDate else { return nil }
    return "Ends \(TimeFormat.time(end))"
}

// MARK: - Lock Screen

private struct LockScreenFocusView: View {
    let context: ActivityViewContext<FocusActivityAttributes>
    /// True when the phone is charging on its side in StandBy.
    @Environment(\.isActivityFullscreen) private var isFullscreen

    var body: some View {
        if isFullscreen {
            StandByFocusView(sessionName: context.attributes.sessionName,
                             state: context.state, done: isDone(context))
        } else {
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        let state = context.state
        let tint = Retro.tint(for: state.phase)
        let done = isDone(context)

        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                LiveDial(reading: TimerReading(state: state, done: done), phase: state.phase)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(done ? "Complete" : (state.isPaused ? "Paused" : state.phase.label))
                        .retroLabel()
                    Text(context.attributes.sessionName)
                        .font(.retro(.headline))
                        .foregroundStyle(Retro.ink)
                        .lineLimit(1)
                    if done {
                        Text(state.phase == .focus ? "Nice work. Take a 5-minute break." : "Break's over. Ready when you are.")
                            .font(.retro(.meta))
                            .foregroundStyle(tint)
                            .lineLimit(2)
                    } else {
                        FocusCountdown(reading: TimerReading(state: state, done: done))
                            .font(.retroDisplay(size: 34))
                            .tracking(-1)
                            .foregroundStyle(Retro.ink)
                            .multilineTextAlignment(.leading)
                        if let ends = endsLine(state, done: done) {
                            Text(ends)
                                .font(.retro(.meta))
                                .foregroundStyle(Retro.inkSoft)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                if !done { PauseResumeButton(isPaused: state.isPaused, tint: tint) }
            }
            SessionPills(completed: state.completedToday ?? 0,
                         inProgress: state.phase == .focus && !done,
                         showsCaption: true, tint: tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 90)
        }
        .padding(18)
    }
}

// MARK: - Pieces

private struct ProgressBar: View {
    let state: FocusActivityAttributes.ContentState
    let done: Bool
    let tint: Color

    var body: some View {
        Group {
            if !done, !state.isPaused, state.endDate != nil {
                ProgressView(timerInterval: state.timerRange, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                let value = done ? 1 : 1 - (state.pausedRemaining ?? 0) / max(state.plannedDuration, 1)
                ProgressView(value: value)
            }
        }
        .progressViewStyle(.linear)
        .tint(tint)
    }
}

#Preview("Lock Screen", as: .content, using: FocusActivityAttributes(sessionName: "Organic chemistry")) {
    FocusLiveActivity()
} contentStates: {
    FocusActivityAttributes.ContentState(session: ActiveSession(
        id: UUID(), name: "Organic chemistry", phase: .focus, plannedDuration: 1500,
        focusStartedAt: .now, state: .running(endDate: .now.addingTimeInterval(900))))
}
