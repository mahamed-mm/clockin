import SwiftUI
import WidgetKit

/// The Live Activity at its smallest: in the Apple Watch Smart Stack (and
/// CarPlay, which can't be told apart). Tick in its live ring, the phase and
/// the time left, and one button: pause or resume while it runs, Start break
/// or Start focus once it's done. Names stay off, beyond a planned next one:
/// a glance, nothing to read.
struct SmallFocusView: View {
    let state: FocusActivityAttributes.ContentState
    let sessionName: String
    let sessionID: UUID?
    let done: Bool

    /// What the one button does. Pure, for the tests.
    enum Action: Equatable { case pauseResume, startBreak, startFocus }

    static func action(phase: SessionPhase, done: Bool) -> Action {
        guard done else { return .pauseResume }
        return phase == .focus ? .startBreak : .startFocus
    }

    var body: some View {
        let tint = Retro.tint(for: state.phase)
        let reading = TimerReading(state: state, done: done)
        HStack(spacing: 8) {
            TickLiveGlyph(pose: TickPose.forLive(phase: state.phase, paused: state.isPaused, done: done),
                          reading: reading, phase: state.phase, crown: false)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(status)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                if done {
                    Text(state.next.map { Copy.nextName($0.name) } ?? state.doneStatus)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    FocusCountdown(reading: reading)
                        .font(.retroDisplay(size: 22))
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 2)
            button(tint: tint)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .contain)
    }

    private var status: String {
        if done { return state.phase == .focus ? Copy.focusComplete : Copy.breakOver }
        return state.isPaused ? Copy.paused : state.phaseLabel
    }

    @ViewBuilder
    private func button(tint: Color) -> some View {
        switch Self.action(phase: state.phase, done: done) {
        case .pauseResume:
            PauseResumeButton(isPaused: state.isPaused, sessionID: sessionID, tint: tint)
        case .startBreak, .startFocus:
            LiveNextAction(state: state, sessionName: sessionName, sessionID: sessionID, done: true,
                           iconOnly: true, height: 34)
        }
    }
}
