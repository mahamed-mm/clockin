import Foundation
import Testing
@testable import Clockin

/// Breathing in time: four in, six out, from when Breathe began, the same
/// whenever it's looked at.
struct BreathCycleTests {
    let cycle = BreathCycle.standard

    @Test func fourInSixOut() {
        #expect(cycle.period == 10)
        #expect(cycle.phase(at: 0) == .init(breathingIn: true, progress: 0, index: 0, start: 0, end: 4))
        #expect(cycle.phase(at: 2).progress == 0.5)
        #expect(cycle.phase(at: 4) == .init(breathingIn: false, progress: 0, index: 1, start: 4, end: 10))
        #expect(cycle.phase(at: 13).breathingIn)
        #expect(cycle.phase(at: 13).index == 2)
        #expect(cycle.phase(at: -3) == cycle.phase(at: 0))
    }

    @Test(arguments: [180.0, 300, 900])
    func turnsComeEveryFourThenSixSeconds(_ length: TimeInterval) {
        let turns = cycle.turns(after: 0, through: length)
        #expect(turns.first == 4)
        #expect(turns.last.map { $0 <= length } == true)
        for (a, b) in zip(turns, turns.dropFirst()) {
            let gap = b - a
            #expect(gap == 4 || gap == 6)
            // In and out take turns.
            #expect(cycle.phase(at: a).breathingIn != cycle.phase(at: b).breathingIn)
        }
        // Two turns a breath, plus one if the break ends mid-breath out.
        let breaths = (length / 10).rounded(.down)
        #expect(turns.count == Int(breaths) * 2 + (length - breaths * 10 >= 4 ? 1 : 0))
    }

    @Test func fullnessIsSmoothAndInRange() {
        var previous = cycle.fullness(at: 0)
        #expect(previous == 0)
        for t in stride(from: 0.01, through: 60, by: 0.01) {
            let now = cycle.fullness(at: t)
            #expect((0...1).contains(now))
            #expect(abs(now - previous) < 0.01, "jump at \(t)")
            previous = now
        }
        #expect(abs(cycle.fullness(at: 4) - 1) < 1e-9)
        #expect(cycle.fullness(at: 2) > 0.4 && cycle.fullness(at: 2) < 0.6)
    }

    @Test func anyMomentLooksTheSameAsSteppingThere() {
        var stepped = 0
        var lastIn = true
        for t in stride(from: 0.0, through: 300, by: 0.25) {
            let phase = cycle.phase(at: t)
            if phase.breathingIn != lastIn { stepped += 1; lastIn = phase.breathingIn }
            #expect(phase.index == stepped)
            #expect(t >= phase.start && t < phase.end)
        }
    }
}

/// A break's own clock, and how the dial reads it.
@MainActor
struct TickBreakTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func breathing(from: TimeInterval = 0) -> TickBreak {
        TickBreak(planned: 300, endDate: start.addingTimeInterval(300), pausedRemaining: nil, style: .breathe, from: from)
    }

    @Test func theStyleCountsFromWhenItBegan() {
        let activity = breathing(from: 60)
        #expect(activity.elapsed(at: start.addingTimeInterval(100)) == 100)
        #expect(activity.styleElapsed(at: start.addingTimeInterval(100)) == 40)
        #expect(activity.styleElapsed(at: start.addingTimeInterval(30)) == 0)
        #expect(activity.styleLength == 240)
        #expect(activity.date(atStyleElapsed: 40) == start.addingTimeInterval(100))
    }

    @Test func pausedItStandsStill() {
        var activity = breathing()
        activity.endDate = nil
        activity.pausedRemaining = 200
        #expect(activity.styleElapsed(at: start) == 100)
        #expect(activity.styleElapsed(at: start.addingTimeInterval(500)) == 100)
        #expect(activity.date(atStyleElapsed: 120) == nil)
        let guide = BreakGuide(activity: activity)
        #expect(guide.changes(after: start).isEmpty)
        // Paused, the dial says so instead.
        #expect(guide.status(at: start) == nil)
    }

    @Test func comesFromTheSession() throws {
        var session = ActiveSession(id: UUID(), name: "", phase: .rest, plannedDuration: 300, focusStartedAt: start,
                                    state: .running(endDate: start.addingTimeInterval(300)),
                                    breakStyle: .breathe, breakStyleFrom: 20)
        let activity = try #require(TickBreak(session: session))
        #expect(activity.style == .breathe && activity.from == 20 && activity.endDate == start.addingTimeInterval(300))
        session.breakStyle = nil
        session.breakStyleFrom = nil
        #expect(TickBreak(session: session)?.style == .rest)
        session.state = .paused(remaining: 120)
        #expect(TickBreak(session: session)?.pausedRemaining == 120)
        session.phase = .focus
        #expect(TickBreak(session: session) == nil)
    }

    @Test func theDialSaysBreatheInAndOut() {
        let guide = BreakGuide(activity: breathing(from: 60))
        #expect(guide.status(at: start.addingTimeInterval(61)) == "Breathe in")
        #expect(guide.status(at: start.addingTimeInterval(65)) == "Breathe out")
        #expect(guide.status(at: start.addingTimeInterval(70)) == "Breathe in")
        let changes = guide.changes(after: start.addingTimeInterval(61))
        #expect(changes.first == start.addingTimeInterval(64))
        #expect(changes.dropFirst().first == start.addingTimeInterval(70))
        #expect(changes.last.map { $0 <= start.addingTimeInterval(300) } == true)
    }

    @Test func voiceOverHearsThePaceNotEachBreath() {
        let guide = BreakGuide(activity: breathing())
        let spoken = Set(stride(from: 0.0, to: 60, by: 0.5).compactMap { guide.spoken(at: start.addingTimeInterval($0)) })
        #expect(spoken == ["Breathe, in for 4 seconds, out for 6"])
    }

    @Test func aRestSaysNothingNew() {
        var activity = breathing()
        activity.style = .rest
        let guide = BreakGuide(activity: activity)
        #expect(guide.status(at: start) == nil && guide.spoken(at: start) == nil && guide.changes(after: start).isEmpty)
    }

    @Test func breathingTickPutsTheMugAway() {
        let loops = TickLoops(pose: .onBreak, seed: 1, entering: true, mug: false)
        #expect(!loops.isContinuous)
        #expect(loops.entryLength == 0)
        #expect(loops.motion(at: 3).steam == 0)
        #expect(TickLoops(pose: .onBreak, seed: 1).isContinuous)
        #expect(TickRig.breathing.mug == 0 && TickRig.breathing.gloves == 0 && TickRig.breathing.headphones == 0)
    }
}
