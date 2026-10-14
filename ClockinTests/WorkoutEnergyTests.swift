import Foundation
import Testing
@testable import Clockin

/// Tick's energy and workout phases, from the timer's length and time left.
struct WorkoutEnergyTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func phase(planned: TimeInterval, left: TimeInterval) -> WorkoutPhase {
        WorkoutEnergy.at(planned: planned, remaining: left).phase
    }

    /// The first second of each phase, as time left, for a session.
    func expectBoundaries(planned: TimeInterval, warmUpEnds: TimeInterval, tiredAt: TimeInterval,
                          exhaustedAt: TimeInterval, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(phase(planned: planned, left: planned) == .warmUp, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: planned - warmUpEnds + 0.1) == .warmUp, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: planned - warmUpEnds) == .strong, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: tiredAt + 0.1) == .strong, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: tiredAt) == .tired, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: exhaustedAt + 0.1) == .tired, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: exhaustedAt) == .exhausted, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: 10.1) == .exhausted, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: 10) == .finalPush, sourceLocation: sourceLocation)
        #expect(phase(planned: planned, left: 0) == .finalPush, sourceLocation: sourceLocation)
    }

    @Test func fiveMinutes() {
        // 10% is shorter than 45 s, 40% shorter than 5 min, 10% shorter than 60 s.
        expectBoundaries(planned: 300, warmUpEnds: 30, tiredAt: 120, exhaustedAt: 30)
    }

    @Test func fifteenMinutes() {
        expectBoundaries(planned: 900, warmUpEnds: 45, tiredAt: 300, exhaustedAt: 60)
    }

    @Test func twentyFiveMinutes() {
        expectBoundaries(planned: 1500, warmUpEnds: 45, tiredAt: 300, exhaustedAt: 60)
    }

    @Test func fiftyMinutes() {
        expectBoundaries(planned: 3000, warmUpEnds: 45, tiredAt: 300, exhaustedAt: 60)
    }

    @Test func aTenSecondTimerIsAllFinalPush() {
        for left in stride(from: 10.0, through: 0, by: -0.5) {
            #expect(phase(planned: 10, left: left) == .finalPush)
        }
        #expect(phase(planned: 0, left: 0) == .finalPush)
    }

    @Test func aMinuteSkipsTheStrongStretch() {
        // 40% left comes before 10% done ends: later phases win.
        #expect(phase(planned: 60, left: 60) == .warmUp)
        #expect(phase(planned: 60, left: 54) == .strong)
        #expect(phase(planned: 60, left: 24) == .tired)
        #expect(phase(planned: 60, left: 6) == .finalPush)
    }

    @Test func energyNeverRisesAsTimePasses() {
        for planned in [10.0, 60, 300, 900, 1500, 3000] {
            var last = 1.0
            for left in stride(from: planned, through: 0, by: -max(0.5, planned / 600)) {
                let energy = WorkoutEnergy.at(planned: planned, remaining: left)
                #expect(energy.energy <= last + 1e-9, "planned \(planned), left \(left)")
                #expect((0...1).contains(energy.energy))
                #expect((0...1).contains(energy.phaseProgress))
                last = energy.energy
            }
        }
        #expect(WorkoutEnergy.at(planned: 1500, remaining: 1500).energy == 1)
    }

    @Test func energyHasNoJumpsBetweenPhases() {
        // Each phase picks up where the last left off.
        let plan = WorkoutEnergy.Plan(planned: 1500)
        for start in [plan.strong, plan.tired, plan.exhausted] {
            let before = WorkoutEnergy.at(planned: 1500, remaining: 1500 - start + 0.001).energy
            let after = WorkoutEnergy.at(planned: 1500, remaining: 1500 - start).energy
            #expect(abs(before - after) < 0.001)
        }
    }

    @Test func phaseStartIsWherePhaseBegan() {
        let tired = WorkoutEnergy.at(planned: 1500, remaining: 200)
        #expect(tired.phase == .tired)
        #expect(tired.phaseStart == 1200)
        #expect(tired.elapsed == 1300)
        #expect(abs(tired.phaseProgress - 100.0 / 240) < 1e-9)
    }

    // MARK: The timer

    @Test func pausedEnergyHoldsAtAnyDate() {
        let paused = TickWorkout(planned: 1500, endDate: nil, pausedRemaining: 200, seed: 1)
        let first = paused.energy(at: now)
        #expect(first.phase == .tired)
        #expect(paused.energy(at: now.addingTimeInterval(3600)) == first)
        #expect(paused.isPaused)
    }

    @Test func resumeCarriesOnFromThePause() {
        // Paused with 200 s left, resumed an hour later: 200 s left again.
        let paused = TickWorkout(planned: 1500, endDate: nil, pausedRemaining: 200, seed: 1)
        let later = now.addingTimeInterval(3600)
        let resumed = TickWorkout(planned: 1500, endDate: later.addingTimeInterval(200), pausedRemaining: nil, seed: 1)
        #expect(resumed.energy(at: later) == paused.energy(at: now))
        #expect(resumed.energy(at: later.addingTimeInterval(150)).phase == .exhausted)
    }

    @Test func extendGivesASecondWind() {
        let tired = WorkoutEnergy.at(planned: 1500, remaining: 200)
        let extended = WorkoutEnergy.at(planned: 1800, remaining: 500)
        #expect(tired.phase == .tired)
        #expect(extended.phase == .strong)
        #expect(extended.energy > tired.energy)
    }

    @Test func timeLeftIsClamped() {
        let running = TickWorkout(planned: 1500, endDate: now.addingTimeInterval(2000), pausedRemaining: nil, seed: 1)
        #expect(running.remaining(at: now) == 1500)
        #expect(running.remaining(at: now.addingTimeInterval(3000)) == 0)
        #expect(running.date(atElapsed: 1500) == now.addingTimeInterval(2000))
    }

    @Test func aSessionAlwaysGetsTheSameSeed() {
        let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        #expect(TickWorkout.seed(from: id) == 0xE621_E1F8_C36C_495A)
        let session = ActiveSession(id: id, name: "Essay", phase: .focus, plannedDuration: 1500,
                                    focusStartedAt: now, state: .paused(remaining: 600))
        let workout = TickWorkout(session: session)
        #expect(workout.seed == 0xE621_E1F8_C36C_495A)
        #expect(workout.remaining(at: now) == 600)
        #expect(workout.isPaused)
    }

    // MARK: Params

    @Test func paramsStayInRange() {
        for planned in [300.0, 1500, 3000] {
            for left in stride(from: planned, through: 0, by: -5) {
                let params = WorkoutParams(WorkoutEnergy.at(planned: planned, remaining: left))
                #expect((0.4...1.3).contains(params.tempo))
                #expect((0.5...1).contains(params.reach))
                #expect(params.rest.lowerBound >= 0 && params.rest.upperBound <= 10)
                #expect((0...1).contains(params.bounce))
                #expect((0.02...0.05).contains(params.breathDepth))
                #expect((0...1).contains(params.sweatRate))
                #expect((0...14).contains(params.hunch))
                #expect((0...6).contains(params.guardDrop))
                #expect((0...1).contains(params.flush))
                if let period = params.breathPeriod { #expect((1.2...2.2).contains(period)) }
            }
        }
    }

    @Test func tiringSlowsAndSweats() {
        func params(_ left: TimeInterval) -> WorkoutParams { WorkoutParams(.at(planned: 1500, remaining: left)) }
        #expect(abs(params(1400).tempo - (1 - 0.15 * 55.0 / 1155)) < 1e-9)
        #expect(params(301).tempo > params(299).tempo - 0.01)
        #expect(params(10.5).tempo < params(299).tempo)
        #expect(params(1400).sweatRate == 0)
        #expect(params(200).sweatRate > 0)
        #expect(params(200).breathPeriod != nil)
        #expect(params(1400).breathPeriod == nil)
        #expect(params(250).face == .determined)
        #expect(params(100).face == .strained)
        #expect(params(30).face == .panting)
        #expect(params(5).tempo == 1.3)
    }
}
