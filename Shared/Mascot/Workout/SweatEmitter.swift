import Foundation

/// A drop of sweat where it is now: relative to the body's centre, in Tick units.
struct SweatDrop: Equatable, Sendable {
    var at: CGPoint
    /// How round the drop is, in Tick units.
    var size: Double
    var opacity: Double
}

/// Tick's sweat, as a function of time: drops spring from the top of the
/// head, drip or are flung off, and fade within a second. They come faster
/// as Tick tires, and every punch thrown tired flings one. Seeded, so the
/// same session sweats the same way every time it's looked at.
struct SweatEmitter: Sendable {
    let planned: TimeInterval
    let seed: UInt64
    /// The punches that fling a drop: every hit thrown tired or in the final push.
    let flings: [TimeInterval]

    /// How long a drop lasts, and how many at most at once.
    static let life = 0.9
    static let cap = 6

    init(planned: TimeInterval, seed: UInt64, scheduler: ComboScheduler) {
        self.planned = planned
        self.seed = seed
        let phases = WorkoutEnergy.Plan(planned: planned)
        var flings: [TimeInterval] = []
        for entry in scheduler.entries {
            let phase = phases.phase(at: entry.start)
            guard phase == .tired || phase == .finalPush else { continue }
            var start = entry.start
            for move in entry.combo.moves {
                flings += move.hits.map { start + $0.at / entry.tempo }
                start += move.duration / entry.tempo
            }
        }
        self.flings = flings
    }

    // MARK: How fast

    /// Drops so far by `elapsed`: the sweat rate (see `WorkoutParams`) added
    /// up, rising from 0.2 to 0.8 a second through the tired stretch and 1 a
    /// second after.
    func count(at elapsed: TimeInterval) -> Double {
        let phases = WorkoutEnergy.Plan(planned: planned)
        let tired = phases.span(of: .tired)
        let length = tired.upperBound - tired.lowerBound
        let x = min(max(0, elapsed - tired.lowerBound), length)
        var n = length > 0 ? 0.2 * x + 0.3 * x * x / length : 0
        if elapsed > phases.exhausted { n += elapsed - phases.exhausted }
        return n
    }

    /// When drop `k` springs: as the count passes k and a bit (jittered).
    func spawnTime(of k: Int) -> TimeInterval {
        let target = Double(k) + 0.3 + 0.4 * noise(k, 0)
        var low = 0.0, high = planned
        guard count(at: high) >= target else { return .infinity }
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if count(at: mid) < target { low = mid } else { high = mid }
        }
        return high
    }

    // MARK: Where

    /// The drops showing at `elapsed`, newest first, at most `cap`.
    func drops(at elapsed: TimeInterval) -> [SweatDrop] {
        var drops: [(born: TimeInterval, drop: SweatDrop)] = []
        let from = elapsed - Self.life
        let first = max(0, Int(count(at: from).rounded(.down)) - 1)
        let last = Int(count(at: elapsed).rounded(.down)) + 1
        if first <= last {
            for k in first...last {
                let born = spawnTime(of: k)
                guard born <= elapsed, born > from else { continue }
                drops.append((born, drip(k, age: elapsed - born)))
            }
        }
        for (index, born) in flings.enumerated() where born <= elapsed && born > from {
            drops.append((born, fling(index, age: elapsed - born)))
        }
        return drops.sorted { $0.born > $1.born }.prefix(Self.cap).map(\.drop)
    }

    /// Off the side of the head: it slides out over the rim and drips away.
    private func drip(_ k: Int, age: TimeInterval) -> SweatDrop {
        let side: Double = noise(k, 1) < 0.5 ? -1 : 1
        let angle = (35 + 30 * noise(k, 2)) * .pi / 180
        let start = CGPoint(x: side * 31 * sin(angle), y: -31 * cos(angle))
        return drop(from: start, velocity: CGPoint(x: side * (6 + 6 * noise(k, 3)), y: 4), gravity: 70, age: age,
                    size: 1.8 + 0.6 * noise(k, 4))
    }

    /// Flung off the top of the head by a punch, in an arc.
    private func fling(_ index: Int, age: TimeInterval) -> SweatDrop {
        let k = -1 - index
        let side: Double = noise(k, 1) < 0.5 ? -1 : 1
        let angle = 20 * noise(k, 2) * .pi / 180
        let start = CGPoint(x: side * 31 * sin(angle), y: -31 * cos(angle))
        return drop(from: start, velocity: CGPoint(x: side * (18 + 8 * noise(k, 3)), y: -22), gravity: 90, age: age,
                    size: 2 + 0.5 * noise(k, 4))
    }

    private func drop(from start: CGPoint, velocity: CGPoint, gravity: Double, age: TimeInterval, size: Double) -> SweatDrop {
        let at = CGPoint(x: start.x + velocity.x * age, y: start.y + velocity.y * age + 0.5 * gravity * age * age)
        // In quickly, then fading as it goes.
        let opacity = min(1, age / 0.08) * (1 - age / Self.life)
        return SweatDrop(at: at, size: size, opacity: max(0, opacity))
    }

    /// A number in 0..<1 for drop `k` and what it's for.
    private func noise(_ k: Int, _ salt: UInt64) -> Double {
        var random = SplitMix64(seed: seed &+ UInt64(bitPattern: Int64(k)) &* 0x9E37_79B9 &+ salt &* 0x85EB_CA6B)
        return Double(random.next() >> 11) / Double(1 << 53)
    }
}
