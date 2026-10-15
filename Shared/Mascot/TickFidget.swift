import Foundation

/// Small things Tick does while it waits, ready and idle: never the same
/// beat twice, so it doesn't look like a loop.
enum TickFidget: CaseIterable, Sendable {
    case crownTap
    case crownPolish
    case dialCheck
    case stretch
    case lookAround
    /// Only late in the day.
    case yawn

    var length: TimeInterval {
        switch self {
        case .crownTap: 0.5
        case .crownPolish: 1.4
        case .dialCheck: 1.3
        case .stretch: 1.6
        case .lookAround: 1.8
        case .yawn: 1.7
        }
    }

    /// The fidget `into` seconds in, added to `motion`.
    func apply(_ into: TimeInterval, to motion: inout TickMotion) {
        let x = min(1, max(0, into / length))
        // Up, held, down: 0 at either end.
        let held = min(1, sin(.pi * x) * 1.6)
        switch self {
        case .crownTap:
            motion.crownTap = sin(.pi * x)
        case .crownPolish:
            // Reaches up and rubs the crown with a little circle.
            motion.crownTap = 0.9 * held
            motion.polish = held * sin(2 * .pi * into * 3.5)
        case .dialCheck:
            // A glance down at the dial, brow up.
            motion.lookX = -3 * held
            motion.lookY = 2.2 * held
            motion.browLift = 1.2 * held
        case .stretch:
            motion.catchReach = 0.7 * held
            motion.lean = 3 * sin(.pi * x)
            motion.squash -= 0.12 * held
        case .lookAround:
            // Left, then right, then back.
            motion.lookX = 3.2 * sin(2 * .pi * x) * held
            motion.lookY = -0.6 * held
        case .yawn:
            motion.catchReach = 0.55 * held
            motion.yawn = held
        }
    }
}

/// When Tick fidgets: a seeded run of fidgets at uneven 8–20 s gaps, the
/// same for the same seed, never one kind twice in a row. Pure, so it can
/// be tested; between fidgets nothing moves, so nothing is drawn.
struct FidgetSchedule: Sendable {
    var seed: Double
    /// Yawns are in the mix (from 20:00).
    var yawns = false

    static let firstAfter: TimeInterval = 3
    static let shortestGap: TimeInterval = 8
    static let longestGap: TimeInterval = 20

    struct Entry: Equatable {
        var fidget: TickFidget
        var start: TimeInterval
        var end: TimeInterval { start + fidget.length }
    }

    /// The fidget going on at `t`, or the next one.
    func entry(from t: TimeInterval) -> Entry {
        var index = 0
        var entry = Entry(fidget: kind(0, after: nil), start: Self.firstAfter + 2 * noise(-7))
        while entry.end <= t {
            index += 1
            let gap = Self.shortestGap + (Self.longestGap - Self.shortestGap) * noise(Double(100 + index))
            entry = Entry(fidget: kind(index, after: entry.fidget), start: entry.end + gap)
        }
        return entry
    }

    /// What's going on at `t`: the fidget and how far into it.
    func current(at t: TimeInterval) -> (TickFidget, TimeInterval)? {
        let entry = entry(from: t)
        return t >= entry.start ? (entry.fidget, t - entry.start) : nil
    }

    func window(from t: TimeInterval) -> Range<TimeInterval> {
        let entry = entry(from: t)
        return entry.start..<entry.end
    }

    private func kind(_ index: Int, after previous: TickFidget?) -> TickFidget {
        let kinds = TickFidget.allCases.filter { (yawns || $0 != .yawn) && $0 != previous }
        let pick = Int(noise(Double(200 + index)) * Double(kinds.count))
        return kinds[min(pick, kinds.count - 1)]
    }

    /// A number in 0..<1 for this seed and index (as `TickLoops` makes them).
    private func noise(_ index: Double) -> Double {
        let x = sin((index + 1) * 12.9898 + seed * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}
