import Foundation

/// Where Tick is in a focus session's workout, from the time left.
enum WorkoutPhase: Int, CaseIterable, Comparable, Sendable {
    /// Bouncing on its toes, arm circles, light jabs, a stretch.
    case warmUp
    /// Full combos, the tempo easing a little over a long session.
    case strong
    /// Slower and weaker, longer rests, breathing hard, sweating.
    case tired
    /// Mostly hands on knees, panting; now and then a weak jab.
    case exhausted
    /// One last flurry of punches, then the bell.
    case finalPush

    static func < (a: WorkoutPhase, b: WorkoutPhase) -> Bool { a.rawValue < b.rawValue }
}

/// Tick's energy through a focus session: a pure function of the planned
/// length and the time left, so it's right however the app got here (back
/// from the background, opened mid-session). Pauses don't count, as the
/// time left stands still while paused.
struct WorkoutEnergy: Equatable, Sendable {
    var phase: WorkoutPhase
    /// 0 at the phase's start to 1 at its end.
    var phaseProgress: Double
    /// 1 fresh to 0 spent; never rises while time passes.
    var energy: Double
    /// Seconds of the session done so far (pauses not counted).
    var elapsed: TimeInterval
    /// When the phase began, in the same seconds as `elapsed`.
    var phaseStart: TimeInterval

    /// Where each phase starts, in seconds done: later phases win where
    /// short sessions make them overlap, and a phase can be empty.
    struct Plan: Equatable, Sendable {
        var planned: TimeInterval
        /// warmUp is the first 45 s, or the first 10% if that's shorter.
        var strong: TimeInterval
        /// From 5 min left, or 40% left if that's shorter.
        var tired: TimeInterval
        /// From 60 s left, or 10% left if that's shorter.
        var exhausted: TimeInterval
        /// The last 10 s.
        var finalPush: TimeInterval

        init(planned: TimeInterval) {
            let planned = max(0, planned)
            self.planned = planned
            finalPush = max(0, planned - 10)
            exhausted = min(finalPush, planned - min(60, 0.1 * planned))
            tired = min(exhausted, planned - min(300, 0.4 * planned))
            strong = min(tired, min(45, 0.1 * planned))
        }

        /// When `phase` starts and ends.
        func span(of phase: WorkoutPhase) -> Range<TimeInterval> {
            switch phase {
            case .warmUp: 0..<strong
            case .strong: strong..<tired
            case .tired: tired..<exhausted
            case .exhausted: exhausted..<finalPush
            case .finalPush: finalPush..<planned
            }
        }

        func phase(at elapsed: TimeInterval) -> WorkoutPhase {
            if elapsed >= finalPush { return .finalPush }
            if elapsed >= exhausted { return .exhausted }
            if elapsed >= tired { return .tired }
            if elapsed >= strong { return .strong }
            return .warmUp
        }
    }

    /// Energy at each phase's start and end: it eases down through warm-up
    /// and the strong stretch, drops through tired, and is nearly gone by
    /// the final push.
    private static let fresh = 1.0, tiring = 0.75, spent = 0.3, empty = 0.1

    static func at(planned: TimeInterval, remaining: TimeInterval) -> WorkoutEnergy {
        let plan = Plan(planned: planned)
        let elapsed = min(plan.planned, max(0, plan.planned - remaining))
        let phase = plan.phase(at: elapsed)
        let span = plan.span(of: phase)
        let progress = span.isEmpty ? 1 : min(1, max(0, (elapsed - span.lowerBound) / (span.upperBound - span.lowerBound)))

        // Warm-up and strong share one gentle slope, so the hand-over is smooth.
        func along(_ range: Range<TimeInterval>, _ from: Double, _ to: Double) -> Double {
            guard !range.isEmpty else { return to }
            let x = min(1, max(0, (elapsed - range.lowerBound) / (range.upperBound - range.lowerBound)))
            return from + (to - from) * x
        }
        let energy = switch phase {
        case .warmUp, .strong: along(0..<plan.tired, fresh, tiring)
        case .tired: along(span, tiring, spent)
        case .exhausted: along(span, spent, empty)
        case .finalPush: empty
        }
        return WorkoutEnergy(phase: phase, phaseProgress: progress, energy: energy, elapsed: elapsed,
                             phaseStart: span.lowerBound)
    }
}
