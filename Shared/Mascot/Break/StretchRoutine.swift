import Foundation

/// The stretches for a break, fitted to the time it has: as many as fit
/// in 60% of it, chosen by how much they help (resting the eyes first),
/// done in an order that flows, with a short pause between, after the mug
/// is put away. The rest of the break is a rest.
struct StretchRoutine: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var move: StretchMove
        var start: TimeInterval
        var end: TimeInterval
    }

    /// The time the routine was fitted to.
    let length: TimeInterval
    let entries: [Entry]

    /// Putting the mug away and standing up.
    static let leadIn: TimeInterval = 1
    /// Standing still between stretches.
    static let gap: TimeInterval = 2
    /// The most of a break the stretches take.
    static let share = 0.6
    /// Which stretches go in first when there isn't time for all.
    static let priority: [StretchMove] = [.eyeRest, .neckRoll, .shoulderShrug, .reachUp, .sideStretch, .wristCircles]

    init(length: TimeInterval) {
        self.length = length
        let budget = length * Self.share - Self.leadIn
        var chosen: Set<StretchMove> = []
        var total = 0.0
        for move in Self.priority {
            let needs = move.duration + (chosen.isEmpty ? 0 : Self.gap)
            guard total + needs <= budget else { continue }
            chosen.insert(move)
            total += needs
        }
        var start = Self.leadIn
        var entries: [Entry] = []
        for move in StretchMove.routine where chosen.contains(move) {
            entries.append(Entry(move: move, start: start, end: start + move.duration))
            start += move.duration + Self.gap
        }
        self.entries = entries
    }

    var count: Int { entries.count }

    /// When the last stretch is over, or 0 when none fit.
    var end: TimeInterval { entries.last?.end ?? 0 }

    /// The stretch under way at `t`.
    func entry(at t: TimeInterval) -> Entry? {
        entries.last { $0.start <= t && t < $0.end }
    }

    /// Which stretch the routine is on at `t`, from 1: the one under way,
    /// or the next one while standing between; nil once it's over.
    func index(at t: TimeInterval) -> Int? {
        guard t < end else { return nil }
        return (entries.firstIndex { t < $0.end } ?? 0) + 1
    }
}

extension StretchMove {
    /// Where the stretch holds still (between moves of the hands and body),
    /// for drawing nothing: worked out once by sampling.
    var stillSpans: [Range<TimeInterval>] { Self.spans[self] ?? [] }

    private static let spans: [StretchMove: [Range<TimeInterval>]] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.findStillSpans()) })

    /// Stretches of at least half a second where nothing moves, sampled 20 times a second.
    private func findStillSpans() -> [Range<TimeInterval>] {
        let step = 0.05
        var spans: [Range<TimeInterval>] = []
        var stillSince: TimeInterval?
        var previous = pose(at: 0)
        var t = step
        while t <= duration {
            let now = pose(at: t)
            let moved = zip(now.animatableData.values, previous.animatableData.values).contains { abs($0 - $1) > 0.002 }
            if moved {
                if let since = stillSince, t - step - since >= 0.5 {
                    // Kept a frame clear of each end, so easing in and out is drawn.
                    spans.append((since + step)..<(t - step))
                }
                stillSince = nil
            } else if stillSince == nil {
                stillSince = t - step
            }
            previous = now
            t += step
        }
        if let since = stillSince, duration - since >= 0.5 { spans.append((since + step)..<duration) }
        return spans
    }
}
