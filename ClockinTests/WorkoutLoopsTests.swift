import Foundation
import SwiftUI
import Testing
@testable import Clockin

/// The workout from the timer's dates, and the frames it asks for.
struct WorkoutLoopsTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A 25-minute session with `left` seconds to go at `now`.
    func loops(left: TimeInterval, paused: Bool = false) -> WorkoutLoops {
        WorkoutLoops(workout: TickWorkout(planned: 1500, endDate: paused ? nil : now.addingTimeInterval(left),
                                          pausedRemaining: paused ? left : nil, seed: 21))
    }

    @Test func movesDuringCombosAndStandsBetween() {
        let loops = loops(left: 900)
        let elapsed = 600.0
        let entry = loops.scheduler.entries.first { $0.start > elapsed }!
        let start = loops.workout.date(atElapsed: entry.start)!
        // Before it: in guard, waiting for the combo.
        let before = start.addingTimeInterval(-0.2)
        #expect(loops.move(at: before) == nil)
        #expect(loops.nextMovement(from: before) == start)
        #expect(loops.frame(at: before).rig == TickRig(workout: WorkoutParams(loops.workout.energy(at: before))))
        // During it: moving, now.
        let during = start.addingTimeInterval(0.1)
        #expect(loops.move(at: during)?.move == entry.combo.moves[0])
        #expect(loops.nextMovement(from: during) == during)
    }

    @Test func theSameMomentLooksTheSameWhenComeBackTo() {
        // Opened mid-combo, or back from the background: the same frame as if watched all along.
        let a = loops(left: 900), b = loops(left: 900)
        let entry = a.scheduler.entries.first { $0.start > 600 && $0.combo.moves.count > 1 }!
        let mid = a.workout.date(atElapsed: entry.start + entry.length / 2)!
        #expect(a.frame(at: mid) == b.frame(at: mid))
        #expect(a.move(at: mid) != nil)
    }

    @Test func pausedHoldsStill() {
        let loops = loops(left: 900, paused: true)
        #expect(loops.nextMovement(from: now) == .distantFuture)
        #expect(loops.move(at: now) == nil)
    }

    @Test func framesOnlyWhileSomethingMoves() {
        // A minute of the strong stretch: 30 frames a second through each
        // combo, and otherwise only the blinks (the workout breathes its own way).
        let loops = loops(left: 900)
        let schedule = TickLoopSchedule(loops: TickLoops(pose: .working, seed: 3, breathes: false), since: now.addingTimeInterval(-60),
                                        pokedAt: nil, paused: false, speed: 1, workout: loops)
        let end = now.addingTimeInterval(60)
        var frames = 0
        for date in schedule.entries(from: now, mode: .normal) {
            guard date < end else { break }
            frames += 1
        }
        let window = loops.workout.energy(at: now).elapsed...loops.workout.energy(at: end).elapsed
        let busy = loops.scheduler.entries.reduce(0.0) { sum, entry in
            sum + max(0, min(entry.end, window.upperBound) - max(entry.start, window.lowerBound))
        }
        #expect(busy > 3)
        #expect(Double(frames) > busy * 30 * 0.9)
        // About 15 blinks a minute, 6 frames each.
        #expect(Double(frames) < busy * 30 + 130, "\(frames) frames for \(busy) s of combos")
        #expect(Double(frames) < 60 * 30 * 0.4)
    }
}
