import SwiftUI

/// Full-screen Live Activity for StandBy (phone charging on its side):
/// a live dial on the left and a bedside-clock countdown on the right.
///
/// StandBy lays this out on the Lock Screen card's canvas (about 360 × 160 pt)
/// and scales it up to fill the display, so sizes here are fixed points for
/// that canvas, not fractions of whatever height the layout happens to get.
/// Everything that moves is system-driven, so it keeps ticking while the
/// app is suspended.
struct StandByFocusView: View {
    let sessionName: String
    let sessionID: UUID?
    let state: FocusActivityAttributes.ContentState
    let done: Bool

    private var reading: TimerReading { TimerReading(state: state, done: done) }
    private var tint: Color { Retro.tint(for: state.phase) }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            LiveDial(reading: reading, phase: state.phase, lineWidthRatio: 0.09)
                .frame(width: 116, height: 116)
                // Tick leans on the dial, as in the app.
                .overlay(alignment: .bottomTrailing) {
                    TickLiveGlyph(pose: TickPose.forLive(phase: state.phase, paused: state.isPaused, done: done),
                                  reading: reading, phase: state.phase)
                        .frame(width: 46, height: 46)
                        .offset(x: 16, y: 10)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(status)
                    .retroLabel()
                Text(Copy.displayName(sessionName))
                    .font(.retroFixed(.text, size: 17))
                    .foregroundStyle(Retro.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)

                if done {
                    Text(state.phase == .focus
                         ? Copy.breakLine(seconds: state.breakDuration ?? Preset.classic.shortBreak)
                         : Copy.readyWhenYouAre)
                        .font(.retroFixed(.title, size: 20))
                        .foregroundStyle(Retro.text(for: state.phase))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                    LiveNextAction(state: state, sessionName: sessionName, sessionID: sessionID, done: true, height: 34)
                        .padding(.top, 6)
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        FocusCountdown(reading: reading)
                            // Fits beside the pause button: live timer text can't shrink.
                            .font(.retroDisplay(size: 44))
                            .foregroundStyle(Retro.ink)
                        Spacer(minLength: 0)
                        PauseResumeButton(isPaused: state.isPaused, sessionID: sessionID, tint: tint, size: 38)
                    }
                    .padding(.top, 2)

                    if state.canExtend == true {
                        LiveNextAction(state: state, sessionName: sessionName, sessionID: sessionID, done: false,
                                       height: 28)
                            .padding(.top, 4)
                    } else {
                        Text(detail)
                            .font(.retroRounded(size: 13))
                            .foregroundStyle(Retro.inkSoft)
                            .lineLimit(1)
                    }
                }

                SessionPills(completed: state.completedToday ?? 0,
                             inProgress: state.phase == .focus && !done,
                             pillWidth: 24, pillHeight: 7,
                             showsCaption: true, tint: tint)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // Each line on its own, so the pause button stays a button.
        .accessibilityElement(children: .contain)
    }

    private var status: String {
        if done { return state.phase == .focus ? Copy.focusComplete : Copy.breakOver }
        return state.isPaused ? Copy.paused : state.phase.label
    }

    private var detail: String {
        if state.isPaused { return Copy.paused }
        guard let end = state.endDate else { return "" }
        return state.phase == .focus ? Copy.ends(end) : Copy.breakUntil(end)
    }
}
