import Foundation
import Testing
@testable import Clockin

/// Which combo Tick throws when, through whole sessions.
struct ComboSchedulerTests {
    static let lengths: [TimeInterval] = [300, 1500, 3000]

    @Test(arguments: lengths)
    func neverTheSameComboTwiceInARow(_ planned: TimeInterval) {
        for seed: UInt64 in [1, 42, 0xE621_E1F8_C36C_495A] {
            let entries = ComboScheduler(planned: planned, seed: seed).entries
            #expect(entries.count > 3)
            for (a, b) in zip(entries, entries.dropFirst()) {
                #expect(a.combo.name != b.combo.name, "\(planned) s, seed \(seed): \(a.combo.name) twice at \(b.start)")
                // One after the other, never overlapping.
                #expect(b.start >= a.end)
            }
        }
    }

    @Test func theSameSeedGivesTheSameSession() {
        #expect(ComboScheduler(planned: 1500, seed: 7) == ComboScheduler(planned: 1500, seed: 7))
        let names = { (seed: UInt64) in ComboScheduler(planned: 1500, seed: seed).entries.map(\.combo.name) }
        #expect(names(7) != names(8))
    }

    @Test(arguments: lengths)
    func eachComboFitsItsPhase(_ planned: TimeInterval) {
        let phases = WorkoutEnergy.Plan(planned: planned)
        for entry in ComboScheduler(planned: planned, seed: 3).entries {
            let phase = phases.phase(at: entry.start)
            #expect(entry.combo.phases.contains(phase), "\(entry.combo.name) in \(phase)")
            // Nothing runs on into the worn-out stretch or the final push.
            if phase < .exhausted { #expect(entry.end <= phases.exhausted + 1e-9) }
            if phase == .exhausted { #expect(entry.end <= phases.finalPush + 1e-9) }
            // Timings are divided by the tempo of the moment it starts.
            let params = WorkoutParams(.at(planned: planned, remaining: planned - entry.start))
            #expect(entry.tempo == params.tempo && entry.reach == params.reach)
        }
    }

    @Test(arguments: lengths)
    func restsGrowAsTickTires(_ planned: TimeInterval) {
        let phases = WorkoutEnergy.Plan(planned: planned)
        let entries = ComboScheduler(planned: planned, seed: 11).entries
        for (a, b) in zip(entries, entries.dropFirst()) where b.combo.name != "final push" {
            let rest = b.start - a.end
            let range = WorkoutParams(.at(planned: planned, remaining: planned - a.end)).rest
            // Waiting for a phase that changes the stance can make a rest longer.
            let waited = [phases.exhausted, phases.finalPush].contains { abs(b.start - $0) < 1e-9 }
            if phases.phase(at: a.start) == .strong {
                #expect((range.lowerBound - 1e-9...12).contains(rest) || waited, "\(a.combo.name) then \(rest) s")
            } else {
                #expect((range.lowerBound - 1e-9...range.upperBound + 1e-9).contains(rest) || waited,
                        "\(phases.phase(at: a.start)): \(rest) s, not \(range)")
            }
        }
    }

    @Test func strongGoesInRounds() {
        let phases = WorkoutEnergy.Plan(planned: 3000)
        let strong = ComboScheduler(planned: 3000, seed: 5).entries.filter { phases.phase(at: $0.start) == .strong }
        let rests = zip(strong, strong.dropFirst()).map { $1.start - $0.end }
        let breaks = rests.filter { $0 >= 8 }
        // A still 8–12 s after every 3 or 4 combos.
        #expect(breaks.count >= strong.count / 4 - 1 && breaks.count <= strong.count / 3 + 1)
        #expect(breaks.allSatisfy { $0 <= 12 })
        // Mostly still: combos fill well under half the strong stretch.
        let busy = strong.reduce(0) { $0 + $1.length }
        #expect(busy / (phases.tired - phases.strong) < 0.5)
    }

    @Test func warmUpStretchesOnce() {
        let entries = ComboScheduler(planned: 1500, seed: 9).entries
        #expect(entries.filter { $0.combo.name == "stretch" }.count == 1)
        #expect(entries[1].combo.name == "stretch")
        #expect(entries[0].combo.phases == [.warmUp])
    }

    @Test(arguments: lengths)
    func theFinalPushStartsTenSecondsFromTheEnd(_ planned: TimeInterval) {
        let last = ComboScheduler(planned: planned, seed: 2).entries.last!
        #expect(last.combo.name == "final push")
        #expect(last.start == planned - 10)
        #expect(last.combo.moves.last == .flurry)
        // The flurry is over just before the bell.
        #expect(last.end <= planned && last.end > planned - 1.5)
    }

    @Test func aTenSecondTimerIsJustTheFinalPush() {
        let entries = ComboScheduler(planned: 10, seed: 1).entries
        #expect(entries.map(\.combo.name) == ["final push"])
        #expect(entries[0].start == 0)
    }

    @Test func anyMomentCanBeLookedUp() {
        // Looking a moment up gives what stepping there from the start does.
        let scheduler = ComboScheduler(planned: 1500, seed: 4)
        for elapsed in stride(from: 0.0, through: 1500, by: 0.37) {
            let stepped = scheduler.entries.last { $0.start <= elapsed && elapsed < $0.end }
            #expect(scheduler.entry(at: elapsed) == stepped)
            if let stepped, let move = scheduler.move(at: elapsed) {
                // In the move's own time, within it.
                #expect(move.t >= 0 && move.t < move.move.duration)
                #expect(stepped.combo.moves.contains(move.move))
            }
        }
        // The first combo waits for the gloves to go on.
        #expect(scheduler.nextStart(after: 0) == ComboScheduler.firstCombo)
        #expect(scheduler.entries[0].start == ComboScheduler.firstCombo)
        #expect(ComboScheduler.firstCombo >= WorkoutLoops.gearUpLength)
        #expect(scheduler.nextStart(after: scheduler.entries[0].start) == scheduler.entries[1].start)
        #expect(scheduler.nextStart(after: 1500) == nil)
    }

    @Test func movesPlayAtTheComboTempo() {
        let scheduler = ComboScheduler(planned: 1500, seed: 4)
        let tired = scheduler.entries.first { $0.start > 1300 && $0.combo.moves.count > 1 }!
        let first = tired.combo.moves[0]
        // Halfway through the first move, in session time, is halfway in move time.
        let half = tired.start + first.duration / tired.tempo / 2
        #expect(abs(scheduler.move(at: half)!.t - first.duration / 2) < 1e-9)
        #expect(scheduler.move(at: tired.start + first.duration / tired.tempo + 0.001)?.move == tired.combo.moves[1])
    }
}
