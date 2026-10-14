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
        // Each combo, then the bounces after it while the round goes on.
        let entries = loops.scheduler.entries
        let busy = zip(entries, entries.dropFirst()).reduce(0.0) { sum, pair in
            let (entry, next) = pair
            let end = entry.end + (next.start - entry.end <= WorkoutLoops.roundGap ? WorkoutLoops.bounceLength : 0)
            return sum + max(0, min(end, window.upperBound) - max(entry.start, window.lowerBound))
        }
        #expect(busy > 3)
        #expect(Double(frames) > busy * 30 * 0.9)
        // About 15 blinks a minute, 6 frames each.
        #expect(Double(frames) < busy * 30 + 130, "\(frames) frames for \(busy) s of combos")
        #expect(Double(frames) < 60 * 30 * 0.55)
    }

    // MARK: Tiring

    @Test func aBlinkHidesEachFaceChange() {
        let loops = loops(left: 900)
        #expect(loops.faceChanges == [1320, 1440, 1490])
        for change in loops.faceChanges {
            #expect(loops.faceBlink(at: change) == 1)
            #expect(loops.faceBlink(at: change - 0.1) == 0 && loops.faceBlink(at: change + 0.1) == 0)
            let before = WorkoutParams(.at(planned: 1500, remaining: 1500 - change + 0.05)).face
            let after = WorkoutParams(.at(planned: 1500, remaining: 1500 - change - 0.05)).face
            #expect(before != after, "at \(change)")
            // Drawn: the eyes are shut right as the face changes.
            #expect(loops.frame(at: loops.workout.date(atElapsed: change)!).motion.blink == 1)
        }
    }

    @Test func breathingHardOnceTired() {
        let loops = loops(left: 900)
        let fresh = loops.workout.date(atElapsed: 1100)!
        #expect(loops.frame(at: fresh).motion.breath == 0)
        // From 5 minutes left it never stops, at 15 frames a second between combos.
        let tired = loops.scheduler.entries.first { $0.start > 1250 }!
        let resting = loops.workout.date(atElapsed: tired.start - 0.5)!
        #expect(loops.nextMovement(from: resting) == resting)
        #expect(loops.frameInterval(at: resting) == 1.0 / 15)
        #expect(loops.frameInterval(at: loops.workout.date(atElapsed: tired.start + 0.1)!) == 1.0 / 30)
        #expect(loops.frame(at: resting).motion.breathDepth > 0.02)
    }

    @Test func breathsQuickenWithoutJumping() {
        let loops = loops(left: 900)
        var last = loops.breath(at: 1200).0
        var peaks: [TimeInterval] = []
        var rising = true
        for step in 1...30_000 {
            let elapsed = 1200 + Double(step) / 100
            let breath = loops.breath(at: elapsed).0
            #expect(abs(breath - last) < 0.05, "at \(elapsed)")
            if rising, breath < last { peaks.append(elapsed) }
            rising = breath >= last
            last = breath
        }
        // 2.2 s apart at first, 1.5 s by the end of tired, 1.2 s worn out.
        let gaps = zip(peaks, peaks.dropFirst()).map { $1 - $0 }
        #expect(abs(gaps.first! - 2.2) < 0.05)
        let lateTired = Array(zip(peaks, gaps)).last { $0.0 < 1435 }!.1
        #expect(abs(lateTired - 1.5) < 0.05)
        #expect(abs(gaps.last! - 1.2) < 0.05)
    }

    @Test func pantingMouthKeepsTime() {
        let loops = loops(left: 900)
        let exhausted = loops.scheduler.entries.first { $0.start > 1445 }!
        let rest = loops.workout.date(atElapsed: exhausted.start - 0.3)!
        let frame = loops.frame(at: rest)
        #expect(frame.face.mouth == .pant)
        #expect(abs(frame.face.mouthOpen - (0.35 + 0.65 * frame.motion.breath)) < 1e-9)
    }

    @Test func theStanceEasesFromOneToTheNext() {
        // Down onto the knees and back up for the final push: no jumps.
        let loops = loops(left: 900)
        for change in [1440.0, 1490] {
            var last = loops.frame(at: loops.workout.date(atElapsed: change - 0.01)!).rig
            for step in 0...20 {
                let rig = loops.frame(at: loops.workout.date(atElapsed: change + Double(step) * 0.03)!).rig
                #expect(abs(rig.centerY - last.centerY) < 1.2 && abs(rig.lean - last.lean) < 2, "at \(change)+\(step)")
                last = rig
            }
            #expect(loops.frameInterval(at: loops.workout.date(atElapsed: change + 0.2)!) == 1.0 / 30)
        }
    }

    @Test func bouncesAfterACombo() {
        let loops = loops(left: 900)
        let entries = loops.scheduler.entries.filter { $0.start > 600 && $0.start < 1100 }
        let params = WorkoutParams(.at(planned: 1500, remaining: 900))
        for (entry, next) in zip(entries, entries.dropFirst()) {
            let inRound = next.start - entry.end <= WorkoutLoops.roundGap
            // A bounce between combos in a round; still after the round.
            #expect((loops.bounce(at: entry.end + 0.2, params: params) < 0) == inRound)
            #expect(loops.bounce(at: entry.end + 1.3, params: params) == 0)
        }
        #expect(entries.contains { _ in true })
        // Once settled it's the plain stance again.
        let entry = entries.first { e in loops.scheduler.nextStart(after: e.start)! - e.end > 1.5 }!
        let settled = loops.frame(at: loops.workout.date(atElapsed: entry.end + 1.3)!).rig
        let stance = TickRig(workout: WorkoutParams(.at(planned: 1500, remaining: 1500 - entry.end - 1.3)))
        #expect(abs(settled.centerY - stance.centerY) < 1e-6 && abs(settled.rightLeg.end.y - stance.rightLeg.end.y) < 1e-6)
    }
}

/// The workout around the session: gloving up, pausing, and the champion.
struct WorkoutAroundTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func glovesGoOnThenTap() {
        let loops = WorkoutLoops(workout: TickWorkout(planned: 1500, endDate: now.addingTimeInterval(1500),
                                                      pausedRemaining: nil, seed: 2))
        let frame = loops.frame(at: now)
        #expect(loops.gearingUp(frame, at: 0).rig.gloves == 0)
        #expect(loops.gearingUp(frame, at: 0.2).rig.gloves > 0.8)
        #expect(loops.gearingUp(frame, at: 0.5).rig.gloves == 1)
        // The gloves meet in front as they tap.
        let tap = loops.gearingUp(frame, at: 0.3 + 0.25).rig
        #expect(abs(tap.leftArm.end.x - tap.rightArm.end.x) < 10)
        #expect(loops.gearingUp(frame, at: WorkoutLoops.gearUpLength).rig.rightArm == frame.rig.rightArm)
    }

    @Test func pausedWornOutKeepsSweatingAndPanting() {
        let paused = WorkoutLoops(workout: TickWorkout(planned: 1500, endDate: nil, pausedRemaining: 30, seed: 2,
                                                       pausedAt: now))
        let frame = paused.pausedFrame(at: now.addingTimeInterval(7.3))
        #expect(frame.rig == .glovedWaiting)
        #expect(frame.face.mouth == .pant && frame.motion.breathDepth == 0.05)
        #expect(paused.pausedMoving)
        #expect(paused.nextMovement(from: now, pose: .waiting, since: now) == now)
        let sweating = (0..<40).contains { !paused.pausedFrame(at: now.addingTimeInterval(Double($0) / 2)).motion.sweat.isEmpty }
        #expect(sweating)
        // Paused fresh: arms crossed, gloves on, still.
        let fresh = WorkoutLoops(workout: TickWorkout(planned: 1500, endDate: nil, pausedRemaining: 900, seed: 2, pausedAt: now))
        #expect(!fresh.pausedMoving)
        #expect(fresh.pausedFrame(at: now.addingTimeInterval(3)).motion == TickMotion())
        #expect(fresh.nextMovement(from: now, pose: .waiting, since: now) == .distantFuture)
    }

    @Test func doneIsTheChampion() {
        let focus = CompletedFocus(id: UUID(), name: "Essay", startedAt: now.addingTimeInterval(-1500), completedAt: now,
                                   focusSeconds: 1500, plannedSeconds: 1500, outcome: .completed)
        let loops = WorkoutLoops(workout: TickWorkout(finished: focus))
        let frame = loops.championFrame(sinceDone: 1)
        #expect(frame.rig == .champion && frame.face.flush > 0)
        #expect(loops.championFrame(sinceDone: 6).motion.sweat.isEmpty)
        #expect(loops.championFrame(sinceDone: 6).face.flush == 0)
        #expect(loops.nextMovement(from: now.addingTimeInterval(2), pose: .done, since: now) == now.addingTimeInterval(2))
        #expect(loops.nextMovement(from: now.addingTimeInterval(6), pose: .done, since: now) == .distantFuture)
        #expect(TickRig.champion.leftArm.end.y < -20 && TickRig.champion.gloves == 1)
    }

    @Test func aPausedSessionRemembersWhen() {
        let session = ActiveSession(id: UUID(), name: "Essay", phase: .focus, plannedDuration: 1500, focusStartedAt: now,
                                    state: .paused(remaining: 600), pausedAt: now)
        #expect(TickWorkout(session: session).pausedAt == now)
    }
}

/// Calm: in guard, tiring in the face, never punching or sweating.
struct WorkoutCalmTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func calm(left: TimeInterval) -> WorkoutLoops {
        WorkoutLoops(workout: TickWorkout(planned: 1500, endDate: now.addingTimeInterval(left), pausedRemaining: nil,
                                          seed: 2, style: .calm))
    }

    @Test func neverPunchesOrSweats() {
        let loops = calm(left: 1500)
        for elapsed in stride(from: 0.0, to: 1500, by: 0.7) {
            let date = now.addingTimeInterval(elapsed)
            let frame = loops.frame(at: date)
            #expect(frame.motion.impact == 0 && frame.motion.sweat.isEmpty && frame.motion.breath == 0)
            // Always in guard, never down on its knees.
            #expect(frame.rig.legFollow == 1)
        }
    }

    @Test func tiresInTheFace() {
        let loops = calm(left: 1500)
        #expect(loops.frame(at: now.addingTimeInterval(600)).face.mouth == .set)
        #expect(loops.frame(at: now.addingTimeInterval(1400)).face.mouth == .gritted)
        #expect(loops.frame(at: now.addingTimeInterval(1470)).face.mouth == .pant)
        #expect(loops.frame(at: now.addingTimeInterval(1440)).motion.blink == 1)
    }

    @Test func onlyMovesToChangeFace() {
        let loops = calm(left: 1500)
        // From the strong stretch, nothing until the blink before the first face change.
        #expect(loops.nextMovement(from: now.addingTimeInterval(600)) == now.addingTimeInterval(1320 - 0.09))
        #expect(!loops.pausedMoving)
        #expect(loops.championFrame(sinceDone: 1).motion.sweat.isEmpty)
        #expect(loops.nextMovement(from: now, pose: .done, since: now) == .distantFuture)
    }
}
