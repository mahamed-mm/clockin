import Foundation

/// Breathing in time: in for `inhale` seconds, out for `exhale`, over and
/// over from the moment the style began. A pure function of time, so the
/// halo, Tick and the dial's words always agree.
struct BreathCycle: Equatable, Sendable {
    var inhale: TimeInterval
    var exhale: TimeInterval

    /// Four in, six out: six breaths a minute, the longer breath out the calming part.
    static let standard = BreathCycle(inhale: 4, exhale: 6)

    var period: TimeInterval { inhale + exhale }

    /// One half of a breath.
    struct Phase: Equatable, Sendable {
        var breathingIn: Bool
        /// 0...1 through it.
        var progress: Double
        /// Halves of breaths before this one, from the start.
        var index: Int
        /// When it began and ends, in the style's time.
        var start: TimeInterval
        var end: TimeInterval
    }

    func phase(at t: TimeInterval) -> Phase {
        let t = max(0, t)
        let breath = (t / period).rounded(.down)
        let into = t - breath * period
        let start = breath * period
        if into < inhale {
            return Phase(breathingIn: true, progress: into / inhale, index: Int(breath) * 2,
                         start: start, end: start + inhale)
        }
        return Phase(breathingIn: false, progress: (into - inhale) / exhale, index: Int(breath) * 2 + 1,
                     start: start + inhale, end: start + period)
    }

    /// How full the lungs are, 0 empty to 1 full, easing in and out of each turn.
    func fullness(at t: TimeInterval) -> Double {
        let phase = phase(at: t)
        let eased = 0.5 - 0.5 * cos(.pi * phase.progress)
        return phase.breathingIn ? eased : 1 - eased
    }

    /// The turns (each breath in and each breath out starting) after `t`, up to `limit`.
    func turns(after t: TimeInterval, through limit: TimeInterval) -> [TimeInterval] {
        var turns: [TimeInterval] = []
        var next = phase(at: t).end
        while next <= limit {
            turns.append(next)
            next = phase(at: next).end
        }
        return turns
    }
}
