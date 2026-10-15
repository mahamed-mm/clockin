import Foundation

/// Tick catching a parked thought: both hands up to take it, a little squash
/// as it lands, then the hands come down and tuck it away behind the ring.
/// Mid-combo, Tick doesn't stop the round: it just nods. Pure functions of
/// the time since the thought was parked, so it can be tested; drawn only
/// while it plays.
enum TickCatch {
    /// The slip's flight to Tick, before the catch.
    static let flight: TimeInterval = 0.55
    static let length: TimeInterval = 0.9
    static let nodLength: TimeInterval = 0.45

    /// How long it plays, once the slip arrives.
    static func duration(nod: Bool) -> TimeInterval { nod ? nodLength : length }

    /// `motion` with the catch (or the nod) `t` seconds after the slip arrived.
    static func apply(to motion: TickMotion, at t: TimeInterval, nod: Bool) -> TickMotion {
        guard t >= 0, t < duration(nod: nod) else { return motion }
        var motion = motion
        if nod {
            // Down and back up: a small "got it".
            motion.bob += 2.5 * sin(.pi * t / nodLength)
            return motion
        }
        motion.catchReach = reach(at: t)
        // It lands in the hands.
        if t >= 0.2, t < 0.4 { motion.squash += 0.25 * sin(.pi * (t - 0.2) / 0.2) }
        return motion
    }

    /// 0...1 of the hands up: up quickly, held, then down to tuck it away.
    static func reach(at t: TimeInterval) -> Double {
        if t < 0.22 { return ease(t / 0.22) }
        if t < 0.5 { return 1 }
        return 1 - ease(min(1, (t - 0.5) / 0.4))
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
