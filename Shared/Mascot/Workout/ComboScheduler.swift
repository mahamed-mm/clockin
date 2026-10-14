import Foundation

/// A run of moves Tick throws in one go, and the phases it belongs to.
struct WorkoutCombo: Equatable, Sendable {
    var name: String
    var moves: [WorkoutMove]
    var phases: Set<WorkoutPhase>

    static let library: [WorkoutCombo] = {
        let full: Set<WorkoutPhase> = [.strong, .tired]
        return [
            // Warming up: bouncing, circling the arms, light jabs.
            WorkoutCombo(name: "bounce", moves: [.guardBounce, .guardBounce], phases: [.warmUp]),
            WorkoutCombo(name: "circles", moves: [.armCircle], phases: [.warmUp]),
            WorkoutCombo(name: "light jabs", moves: [.lightJab, .lightJab], phases: [.warmUp]),
            WorkoutCombo(name: "jab and circle", moves: [.lightJab, .armCircle], phases: [.warmUp]),
            // The workout proper.
            WorkoutCombo(name: "jab-jab-cross", moves: [.jab, .jab, .cross], phases: [.strong]),
            WorkoutCombo(name: "jab-cross-hook", moves: [.jab, .cross, .hook], phases: [.strong]),
            WorkoutCombo(name: "cross-uppercut", moves: [.cross, .uppercut], phases: full),
            WorkoutCombo(name: "frontKick-jab", moves: [.frontKick, .jab], phases: full),
            WorkoutCombo(name: "duck-hook", moves: [.duck, .hook], phases: full),
            WorkoutCombo(name: "sideKick", moves: [.sideKick], phases: [.strong]),
            WorkoutCombo(name: "hook-uppercut-cross", moves: [.hook, .uppercut, .cross], phases: [.strong]),
            WorkoutCombo(name: "jab-cross", moves: [.jab, .cross], phases: full),
            WorkoutCombo(name: "jab", moves: [.jab], phases: [.tired]),
            // Worn out.
            WorkoutCombo(name: "wipe", moves: [.wipe], phases: [.exhausted]),
            WorkoutCombo(name: "weak jab", moves: [.weakJab], phases: [.exhausted]),
        ]
    }()

    /// Once, early in the warm-up.
    static let stretch = WorkoutCombo(name: "stretch", moves: [.stretch], phases: [.warmUp])

    /// The last 10 seconds: bouncing, pumped, then one flurry that ends
    /// just before the bell.
    static func finalPush(lasting span: TimeInterval, tempo: Double) -> WorkoutCombo {
        let flurry = WorkoutMove.flurry.duration / tempo, bounce = WorkoutMove.guardBounce.duration / tempo
        let bounces = max(0, Int(((span - flurry - 0.5) / bounce).rounded(.down)))
        return WorkoutCombo(name: "final push", moves: Array(repeating: .guardBounce, count: bounces) + [.flurry],
                            phases: [.finalPush])
    }
}

/// When Tick throws which combo through a whole session: decided once
/// from the session's seed and length, so it's the same however often the
/// app is opened, and any moment can be looked up directly.
///
/// - Never the same combo twice in a row.
/// - Rests in guard between combos, from how tired Tick is: 1–2 s when
///   strong, longer as it tires. While strong it goes in rounds of 3–4
///   combos with 8–12 s still between them.
/// - Every move's time is divided by the tempo when its combo starts.
/// - A combo never runs into the worn-out stretch or the final push.
struct ComboScheduler: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var combo: WorkoutCombo
        /// Seconds of the session done when it starts (pauses not counted).
        var start: TimeInterval
        var tempo: Double
        var reach: Double

        var length: TimeInterval { combo.moves.reduce(0) { $0 + $1.duration } / tempo }
        var end: TimeInterval { start + length }
    }

    let planned: TimeInterval
    let seed: UInt64
    private(set) var entries: [Entry] = []

    /// When the first combo can start: after gloving up.
    static let firstCombo = 1.5

    /// Combos in a round, and the still stretch between rounds.
    static let roundSize = 3...4
    static let roundRest = 8.0...12.0

    init(planned: TimeInterval, seed: UInt64) {
        self.planned = planned
        self.seed = seed
        entries = Self.plan(planned: planned, seed: seed)
    }

    /// The move under way `elapsed` seconds into the session, how far into
    /// it (in the move's own time, tempo applied), and how far it reaches.
    func move(at elapsed: TimeInterval) -> (move: WorkoutMove, t: TimeInterval, reach: Double)? {
        guard let entry = entry(at: elapsed) else { return nil }
        var t = (elapsed - entry.start) * entry.tempo
        for move in entry.combo.moves {
            if t < move.duration { return (move, t, entry.reach) }
            t -= move.duration
        }
        return nil
    }

    /// The combo under way at `elapsed`, if any.
    func entry(at elapsed: TimeInterval) -> Entry? {
        guard let index = lastStarted(by: elapsed) else { return nil }
        return elapsed < entries[index].end ? entries[index] : nil
    }

    /// When the last combo over by `elapsed` ended.
    func lastEnd(by elapsed: TimeInterval) -> TimeInterval? {
        guard let index = lastStarted(by: elapsed) else { return nil }
        if entries[index].end <= elapsed { return entries[index].end }
        return index > 0 ? entries[index - 1].end : nil
    }

    /// The last combo starting at or before `elapsed`, by halving.
    private func lastStarted(by elapsed: TimeInterval) -> Int? {
        var low = 0, high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].start <= elapsed { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }

    /// The start of the next combo after `elapsed`.
    func nextStart(after elapsed: TimeInterval) -> TimeInterval? {
        entries.first { $0.start > elapsed }?.start
    }

    // MARK: Planning

    private static func plan(planned: TimeInterval, seed: UInt64) -> [Entry] {
        let phases = WorkoutEnergy.Plan(planned: planned)
        var random = SplitMix64(seed: seed)
        var entries: [Entry] = []
        // The first combo after the gloves go on.
        var time = min(firstCombo, phases.finalPush)
        var stretched = false
        var inRound = 0
        var roundLength = Int.random(in: roundSize, using: &random)

        while time < phases.finalPush {
            let energy = WorkoutEnergy.at(planned: planned, remaining: planned - time)
            let params = WorkoutParams(energy)
            // A combo must be over before the stance changes for the worn-out
            // stretch, and before the final push.
            let wall = energy.phase < .exhausted ? phases.exhausted : phases.finalPush

            let combo: WorkoutCombo
            if energy.phase == .warmUp, !stretched, !entries.isEmpty {
                combo = WorkoutCombo.stretch
                stretched = true
            } else {
                let choices = WorkoutCombo.library.filter { $0.phases.contains(energy.phase) && $0.name != entries.last?.combo.name }
                guard !choices.isEmpty else { time = wall; continue }
                combo = choices[Int.random(in: 0..<choices.count, using: &random)]
            }
            let entry = Entry(combo: combo, start: time, tempo: params.tempo, reach: params.reach)
            guard entry.end <= wall else {
                time = wall
                continue
            }
            entries.append(entry)

            // Rest in guard; while strong, a longer still stretch after each round.
            let after = WorkoutParams(.at(planned: planned, remaining: planned - entry.end))
            var rest = Double.random(in: after.rest, using: &random)
            if energy.phase == .strong {
                inRound += 1
                if inRound >= roundLength {
                    rest = Double.random(in: roundRest, using: &random)
                    inRound = 0
                    roundLength = Int.random(in: roundSize, using: &random)
                }
            }
            time = entry.end + rest
        }

        // The final push, from 10 s left, whatever came before.
        let span = phases.span(of: .finalPush)
        let push = WorkoutParams(.at(planned: planned, remaining: planned - span.lowerBound))
        if !span.isEmpty {
            if let last = entries.last, last.end > span.lowerBound { entries.removeLast() }
            entries.append(Entry(combo: .finalPush(lasting: span.upperBound - span.lowerBound, tempo: push.tempo),
                                 start: span.lowerBound, tempo: push.tempo, reach: push.reach))
        }
        return entries
    }
}

/// A small, fast random number generator with a seed: the same seed gives
/// the same numbers on every device and every launch.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
