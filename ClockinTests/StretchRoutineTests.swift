import Foundation
import Testing
@testable import Clockin

/// The stretches fitted to a break, and Tick leading them at any moment.
@MainActor
struct StretchRoutineTests {
    @Test func aShortBreakGetsFewerStretches() {
        #expect(StretchRoutine(length: 5).count == 0)
        #expect(StretchRoutine(length: 15).count == 0)
        #expect(StretchRoutine(length: 180).count == 4)
        #expect(StretchRoutine(length: 300).count == 6)
        #expect(StretchRoutine(length: 600).count == 6)
        #expect(StretchRoutine(length: 900).count == 6)
    }

    @Test(arguments: [60.0, 120, 180, 240, 300, 600, 900])
    func neverMoreThanItsShare(_ length: TimeInterval) {
        let routine = StretchRoutine(length: length)
        #expect(routine.end <= length * StretchRoutine.share + 1e-9)
        for (a, b) in zip(routine.entries, routine.entries.dropFirst()) {
            #expect(b.start - a.end == StretchRoutine.gap)
        }
        #expect(routine.entries.first.map { $0.start == StretchRoutine.leadIn } ?? true)
    }

    @Test func theEyesRestFirstWhenThereIsLittleTime() {
        // Done in routine order, chosen by priority.
        let short = StretchRoutine(length: 180).entries.map(\.move)
        #expect(short == [.neckRoll, .shoulderShrug, .reachUp, .eyeRest])
        #expect(StretchRoutine(length: 300).entries.map(\.move) == StretchMove.routine)
        #expect(StretchRoutine(length: 60).entries.map(\.move) == [.eyeRest])
    }

    @Test func anyMomentLooksTheSameAsSteppingThere() {
        let routine = StretchRoutine(length: 300)
        var index = 1
        for t in stride(from: 0.0, to: routine.end, by: 0.1) {
            let stepped = routine.entries.last { $0.start <= t && t < $0.end }
            #expect(routine.entry(at: t) == stepped)
            if let i = routine.index(at: t) {
                #expect(i >= index)
                index = i
            }
        }
        #expect(index == routine.count)
        #expect(routine.index(at: routine.end) == nil)
    }

    // MARK: Leading it

    let start = Date(timeIntervalSinceReferenceDate: 0)

    func stretching(_ planned: TimeInterval = 300, from: TimeInterval = 0) -> TickBreak {
        TickBreak(planned: planned, endDate: start.addingTimeInterval(planned), pausedRemaining: nil,
                  style: .stretch, from: from)
    }

    @Test func tickStretchesThenRestsWithTheMug() throws {
        let loops = BreakLoops(activity: stretching())
        let end = loops.routine.end
        // Up off the ground, the mug away.
        let early = try #require(loops.frame(at: start.addingTimeInterval(0.1)))
        #expect(early.rig.mug > 0.5)
        let up = try #require(loops.frame(at: start.addingTimeInterval(1.5)))
        #expect(up.rig.mug == 0)
        // Mid-routine it's doing the stretch of the moment.
        let entry = loops.routine.entries[2]
        let mid = try #require(loops.frame(at: start.addingTimeInterval(entry.start + 6)))
        #expect(mid.rig == TickRig.standing.applying(entry.move.pose(at: 6)))
        // Done: down with the mug, then simply resting.
        #expect(loops.frame(at: start.addingTimeInterval(end + BreakLoops.blend / 2))?.rig.mug ?? 0 > 0)
        #expect(loops.frame(at: start.addingTimeInterval(end + BreakLoops.blend + 0.01)) == nil)
        #expect(!loops.leads(at: start.addingTimeInterval(end + 1)))
        #expect(loops.rejoinsRest == end + BreakLoops.blend)
    }

    @Test func switchingMidBreakFitsWhatsLeft() {
        let loops = BreakLoops(activity: stretching(300, from: 180))
        #expect(loops.routine.length == 120)
        #expect(loops.routine.count == 3)
        #expect(loops.frame(at: start.addingTimeInterval(100)) != nil)
    }

    @Test func framesOnlyWhileSomethingMoves() {
        // Counted the way the screen asks for them, over the whole routine.
        let loops = BreakLoops(activity: stretching())
        var date = start
        var frames = 0
        let end = start.addingTimeInterval(loops.routine.end + 2)
        while date < end {
            let next = loops.nextMovement(from: date)
            guard next < end else { break }
            frames += 1
            date = max(next, date).addingTimeInterval(loops.frameInterval(at: date))
        }
        let busy = loops.routine.end * 30
        // Holds, eye rest and the gaps between stretches draw nothing.
        #expect(frames > 1000 && Double(frames) < busy * 0.8, "\(frames) of \(busy)")
        #expect(loops.nextMovement(from: end) == .distantFuture)
    }

    @Test func pausedItHoldsStill() {
        var activity = stretching()
        activity.endDate = nil
        activity.pausedRemaining = 260
        let loops = BreakLoops(activity: activity)
        #expect(loops.frame(at: start) == loops.frame(at: start.addingTimeInterval(500)))
        #expect(loops.nextMovement(from: start) == .distantFuture)
    }

    @Test func stillsChangeOnlyBetweenStretches() {
        let loops = BreakLoops(activity: stretching())
        let changes = loops.stillChanges(after: start)
        #expect(changes.count == loops.routine.count * 2)
        let entry = loops.routine.entries[1]
        let a = loops.stillFrame(at: start.addingTimeInterval(entry.start + 1))
        let b = loops.stillFrame(at: start.addingTimeInterval(entry.end - 1))
        #expect(a == b)
        #expect(a?.rig == TickRig.standing.applying(entry.move.stillPose))
        #expect(loops.stillKey(at: start.addingTimeInterval(entry.start + 1)) == entry.move.rawValue)
        #expect(loops.stillFrame(at: start.addingTimeInterval(loops.routine.end + 5)) == nil)
    }

    @Test func theDialNamesTheStretch() {
        let guide = BreakGuide(activity: stretching())
        let entries = guide.routine.entries
        #expect(guide.status(at: start.addingTimeInterval(entries[0].start + 2)) == "Neck roll")
        #expect(guide.step(at: start.addingTimeInterval(entries[1].start + 2))! == (2, 6))
        // Standing between, it names the next one.
        #expect(guide.status(at: start.addingTimeInterval(entries[1].end + 1)) == "Reach up")
        #expect(guide.spoken(at: start.addingTimeInterval(entries[1].start + 2)) == "Stretch, 2 of 6, shoulder shrug")
        #expect(guide.spoken(at: start.addingTimeInterval(entries[5].start + 2)) == "Stretch, 6 of 6, look at something far away")
        // Done: the usual label and nothing extra to hear.
        let after = start.addingTimeInterval(guide.routine.end + 1)
        #expect(guide.status(at: after) == nil && guide.step(at: after) == nil && guide.spoken(at: after) == nil)
        #expect(guide.changes(after: start).count == entries.count)
    }
}
