import AppIntents
import SwiftUI

/// How a timer should be drawn outside the app (Live Activity, widget,
/// StandBy), where nothing can redraw a custom view between updates.
/// Every surface shows time left, draining, like the app's dial: a ring or
/// bar is full at the start, empties as time passes, and a finished phase
/// shows a full mustard ring.
enum TimerReading: Equatable {
    /// Running: the system animates anything built from this range.
    case running(ClosedRange<Date>)
    /// Paused: a frozen fraction of time left and the seconds left.
    case paused(fraction: Double, remaining: TimeInterval)
    case done

    init(state: FocusActivityAttributes.ContentState, done: Bool) {
        if done {
            self = .done
        } else if let remaining = state.pausedRemaining {
            self = .paused(fraction: min(1, remaining / max(state.plannedDuration, 1)), remaining: remaining)
        } else {
            self = .running(state.timerRange)
        }
    }

    init(session: ActiveSession, at now: Date) {
        switch session.state {
        case .running(let end) where end > now:
            self = .running(end.addingTimeInterval(-session.plannedDuration)...end)
        case .running:
            self = .done
        case .paused(let remaining):
            self = .paused(fraction: min(1, remaining / max(session.plannedDuration, 1)), remaining: remaining)
        }
    }
}

extension SessionPhase {
    var symbol: String { self == .focus ? "timer" : "cup.and.saucer.fill" }
}

/// The app's dial face with Apple's self-updating circular timer laid on its
/// track. The ring keeps moving on the Lock Screen and in StandBy without app
/// updates; a custom knob can't, so this version leaves it out.
struct LiveDial<Center: View>: View {
    let reading: TimerReading
    let phase: SessionPhase
    var lineWidthRatio: CGFloat = 0.1
    var showsTicks = true
    @ViewBuilder var center: () -> Center

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ring = side * RetroDial.arcRadiusRatio(showsTicks: showsTicks)
            ZStack {
                Group {
                    RetroDial(value: 0, tint: tint, showsTicks: showsTicks, showsKnob: false,
                              lineWidthRatio: lineWidthRatio)
                    timerRing
                        .progressViewStyle(.circular)
                        .tint(tint)
                        .frame(width: ring, height: ring)
                }
                // The ring is decoration; whatever sits in the middle (a
                // countdown, say) is still read.
                .accessibilityHidden(true)
                center()
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var tint: Color {
        reading == .done ? Retro.mustard : Retro.tint(for: phase)
    }

    @ViewBuilder
    private var timerRing: some View {
        switch reading {
        case .done:
            ProgressView(value: 1)
        case .paused(let fraction, _):
            ProgressView(value: fraction)
        case .running(let range):
            ProgressView(timerInterval: range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
    }
}

extension LiveDial where Center == LiveDialSymbol {
    /// Dial with the phase symbol in the middle.
    init(reading: TimerReading, phase: SessionPhase, lineWidthRatio: CGFloat = 0.1) {
        self.init(reading: reading, phase: phase, lineWidthRatio: lineWidthRatio) {
            LiveDialSymbol(symbol: reading == .done ? "checkmark" : phase.symbol)
        }
    }
}

/// Phase glyph sized to the dial.
struct LiveDialSymbol: View {
    let symbol: String

    var body: some View {
        GeometryReader { proxy in
            Image(systemName: symbol)
                .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.2, weight: .bold))
                .foregroundStyle(Retro.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// Countdown text that keeps ticking without app updates while running.
struct FocusCountdown: View {
    let reading: TimerReading

    var body: some View {
        switch reading {
        case .done: fitted(Text(verbatim: "00:00"))
        case .paused(_, let remaining): fitted(Text(TimeFormat.clock(remaining)))
        case .running(let range):
            // The system lays out live timer text itself; with a scale factor
            // it shrinks Fraunces to half whatever the room, so callers size
            // the font to fit instead.
            Text(timerInterval: range, countsDown: true)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func fitted(_ text: Text) -> some View {
        text.monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Round pause/resume button that runs in the app process via an App Intent.
struct PauseResumeButton: View {
    let isPaused: Bool
    /// The session the card shows; the intent ignores taps meant for another.
    let sessionID: UUID?
    let tint: Color
    var size: CGFloat = 44

    var body: some View {
        Button(intent: PauseResumeIntent(pause: !isPaused, sessionID: sessionID)) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Resume" : "Pause")
    }
}

/// A Lock Screen action as a tinted capsule, the same family as the pause
/// button: Start break, Start focus, "+5 min". In StandBy's night view it
/// turns to an outline, which the red night tint keeps readable. Runs its
/// intent in the app.
struct LiveActionButton<Intent: AppIntent>: View {
    let intent: Intent
    let title: String
    let symbol: String
    let tint: Color
    /// What VoiceOver reads, when the title reads badly ("+5 min").
    var spoken: String? = nil
    /// Just the symbol, in a circle (the compact island).
    var iconOnly = false
    var height: CGFloat = 38
    @Environment(\.isLuminanceReduced) private var night

    var body: some View {
        Button(intent: intent) {
            Group {
                if iconOnly {
                    Image(systemName: symbol)
                        .frame(width: height, height: height)
                } else {
                    Label(title, systemImage: symbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .frame(height: height)
                }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(night ? tint : .white)
            .background {
                Capsule()
                    .fill(night ? Color.clear : tint)
                    .strokeBorder(tint, lineWidth: night ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? title)
    }
}

/// What the Lock Screen offers next: Start break once focus is done, Start
/// focus with the same name once a break is, and "+5 min" in the last five
/// minutes of focus. Nothing otherwise.
struct LiveNextAction: View {
    let state: FocusActivityAttributes.ContentState
    let sessionName: String
    let sessionID: UUID?
    let done: Bool
    var iconOnly = false
    var height: CGFloat = 38

    var body: some View {
        if done {
            if state.phase == .focus {
                LiveActionButton(intent: sessionID.map(StartBreakIntent.init(sessionID:)) ?? StartBreakIntent(),
                                 title: Copy.startBreakShort, symbol: "cup.and.saucer.fill", tint: Retro.avocado,
                                 iconOnly: iconOnly, height: height)
            } else {
                LiveActionButton(intent: StartFocusIntent(name: sessionName), title: Copy.startFocus,
                                 symbol: "play.fill", tint: Retro.orange, iconOnly: iconOnly, height: height)
            }
        } else if state.phase == .focus, state.canExtend == true {
            LiveActionButton(intent: ExtendFocusIntent(sessionID: sessionID),
                             title: Copy.extend(seconds: SessionEngine.extensionStep), symbol: "plus",
                             tint: Retro.orange, spoken: Copy.extendSpoken(seconds: SessionEngine.extensionStep),
                             iconOnly: iconOnly, height: height)
        }
    }
}
