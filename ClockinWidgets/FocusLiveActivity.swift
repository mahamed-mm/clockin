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
                    Label {
                        // "Break's over" once it ran out, not "Break" over 00:00.
                        Text(done ? state.doneStatus : state.phaseLabel)
                    } icon: {
                        TickLiveGlyph(pose: TickPose.forLive(phase: state.phase, paused: state.isPaused, done: done),
                                      reading: TimerReading(state: state, done: done), phase: state.phase, crown: false)
                            .frame(width: 26, height: 26)
                    }
                    .font(.retro(.label))
                    .foregroundStyle(tint)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if done {
                        LiveNextAction(state: state, sessionName: context.attributes.sessionName,
                                       sessionID: context.attributes.sessionID, done: true, iconOnly: true, height: 44)
                    } else {
                        PauseResumeButton(isPaused: state.isPaused, sessionID: context.attributes.sessionID, tint: tint)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        Image(systemName: state.nameSymbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(Copy.displayName(context.attributes.sessionName))
                            .retroFont(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        FocusCountdown(reading: TimerReading(state: state, done: done))
                            .font(.retroDisplay(size: 40))
                            .multilineTextAlignment(.center)
                        ProgressBar(reading: TimerReading(state: state, done: done), tint: tint)
                        if let ends = endsLine(state, done: done) {
                            Text(ends).font(.retro(.meta)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                // Tick's face in a live ring: its eyes and the time left say how things stand.
                TickLiveGlyph(pose: TickPose.forLive(phase: state.phase, paused: state.isPaused, done: done),
                              reading: TimerReading(state: state, done: done), phase: state.phase, crown: false)
                    .frame(width: 24, height: 24)
                    .accessibilityElement()
                    .accessibilityLabel(cardStatus(state, done: done))
            } compactTrailing: {
                FocusCountdown(reading: TimerReading(state: state, done: done))
                    .font(.retroDisplay(size: 17))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 52)
                    .foregroundStyle(tint)
            } minimal: {
                // Sharing the island: Tick's face inside the live ring.
                TickLiveGlyph(pose: TickPose.forLive(phase: state.phase, paused: state.isPaused, done: done),
                              reading: TimerReading(state: state, done: done), phase: state.phase, crown: false)
                    .accessibilityElement()
                    .accessibilityLabel(cardStatus(state, done: done))
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
    return Copy.ends(end)
}

/// The small label over the name: the phase, "Paused", or how it ended.
private func cardStatus(_ state: FocusActivityAttributes.ContentState, done: Bool) -> String {
    if done { return state.doneStatus }
    return state.isPaused ? Copy.paused : state.phaseLabel
}

// MARK: - Lock Screen

private struct LockScreenFocusView: View {
    let context: ActivityViewContext<FocusActivityAttributes>
    /// True when the phone is charging on its side in StandBy.
    @Environment(\.isActivityFullscreen) private var isFullscreen

    var body: some View {
        if isFullscreen {
            StandByFocusView(sessionName: context.attributes.sessionName, sessionID: context.attributes.sessionID,
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
                    .overlay(alignment: .bottomTrailing) {
                        TickLiveGlyph(pose: TickPose.forLive(phase: state.phase, paused: state.isPaused, done: done),
                                      reading: TimerReading(state: state, done: done), phase: state.phase)
                            .frame(width: 32, height: 32)
                            .offset(x: 9, y: 7)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardStatus(state, done: done))
                        .retroLabel()
                    HStack(spacing: 6) {
                        Image(systemName: state.nameSymbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Retro.inkSoft)
                            .accessibilityHidden(true)
                        Text(Copy.displayName(context.attributes.sessionName))
                            .retroFont(.headline)
                            .foregroundStyle(Retro.ink)
                            .lineLimit(1)
                    }
                    if done {
                        Text(state.doneLine)
                            .font(.retro(.meta))
                            .foregroundStyle(Retro.text(for: state.phase))
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
                if done {
                    // Round, like Pause: the line beside it says what it starts.
                    LiveNextAction(state: state, sessionName: context.attributes.sessionName,
                                   sessionID: context.attributes.sessionID, done: true, iconOnly: true, height: 44)
                } else {
                    VStack(spacing: 8) {
                        PauseResumeButton(isPaused: state.isPaused, sessionID: context.attributes.sessionID, tint: tint)
                        if state.canExtend == true {
                            LiveNextAction(state: state, sessionName: context.attributes.sessionName,
                                           sessionID: context.attributes.sessionID, done: false, height: 32)
                        } else if state.phase == .focus {
                            // Opens the app to the park field. The thought itself never shows here.
                            Link(destination: URL(string: "clockin://park")!) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Retro.ink)
                                    .frame(width: 44, height: 32)
                                    .background(Retro.ink.opacity(0.08), in: .capsule)
                            }
                            .accessibilityLabel(Copy.parkThought)
                        }
                    }
                }
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

/// Time left, draining, like every other timer in the app.
private struct ProgressBar: View {
    let reading: TimerReading
    let tint: Color

    var body: some View {
        Group {
            switch reading {
            case .running(let range):
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            case .paused(let fraction, _):
                ProgressView(value: fraction)
            case .done:
                ProgressView(value: 1)
            }
        }
        .progressViewStyle(.linear)
        .tint(reading == .done ? Retro.mustard : tint)
    }
}

#Preview("Lock Screen", as: .content, using: FocusActivityAttributes(sessionName: "Organic chemistry")) {
    FocusLiveActivity()
} contentStates: {
    FocusActivityAttributes.ContentState(session: ActiveSession(
        id: UUID(), name: "Organic chemistry", phase: .focus, plannedDuration: 1500,
        focusStartedAt: .now, state: .running(endDate: .now.addingTimeInterval(900))))
}
