import Foundation
import Testing
@testable import Clockin

/// Tick's sweat: when drops come, where they go, and that there are never too many.
struct SweatEmitterTests {
    static func emitter(planned: TimeInterval = 1500, seed: UInt64 = 8) -> SweatEmitter {
        SweatEmitter(planned: planned, seed: seed, scheduler: ComboScheduler(planned: planned, seed: seed))
    }

    /// Drops springing in a stretch of the session (not counting flung ones).
    static func spawns(_ emitter: SweatEmitter, in range: Range<TimeInterval>) -> Int {
        (0..<4000).map(emitter.spawnTime).filter { range.contains($0) }.count
    }

    @Test func noSweatUntilTired() {
        let emitter = Self.emitter()
        #expect(emitter.count(at: 1199) == 0)
        for elapsed in stride(from: 0.0, to: 1200, by: 7) { #expect(emitter.drops(at: elapsed).isEmpty) }
        #expect(emitter.flings.allSatisfy { $0 >= 1200 })
    }

    @Test func theRateFollowsTheParams() {
        // Counted drops a second match WorkoutParams' sweat rate through the session.
        let emitter = Self.emitter()
        for elapsed in stride(from: 1210.0, to: 1490, by: 20) {
            let rate = (emitter.count(at: elapsed + 0.5) - emitter.count(at: elapsed - 0.5))
            let params = WorkoutParams(.at(planned: 1500, remaining: 1500 - elapsed))
            #expect(abs(rate - params.sweatRate) < 0.01, "at \(elapsed)")
        }
    }

    @Test func dropsComeFasterAsTickTires() {
        let emitter = Self.emitter()
        let early = Self.spawns(emitter, in: 1200..<1260)
        let late = Self.spawns(emitter, in: 1380..<1440)
        let wornOut = Self.spawns(emitter, in: 1440..<1490)
        #expect(early < late && late < wornOut + 10)
        // 0.2 rising to 0.8 a second over the 4 tired minutes, then 1 a second.
        #expect((15...18).contains(early) && (42...45).contains(late) && (48...52).contains(wornOut))
    }

    @Test func tiredPunchesFlingDrops() {
        let emitter = Self.emitter()
        #expect(!emitter.flings.isEmpty)
        let fling = emitter.flings[0]
        #expect(emitter.drops(at: fling + 0.1).count > Self.emitter().drops(at: fling - 0.01).count
                || emitter.drops(at: fling + 0.1).count == SweatEmitter.cap)
        // The final push's flurry flings six.
        #expect(emitter.flings.filter { $0 >= 1490 }.count == 6)
    }

    @Test func neverMoreThanTheCap() {
        let emitter = Self.emitter()
        var most = 0
        for elapsed in stride(from: 1200.0, through: 1500, by: 0.05) {
            let count = emitter.drops(at: elapsed).count
            #expect(count <= SweatEmitter.cap)
            most = max(most, count)
        }
        #expect(most >= 2)
    }

    @Test func theSameSeedSweatsTheSame() {
        #expect(Self.emitter(seed: 3).drops(at: 1470) == Self.emitter(seed: 3).drops(at: 1470))
        let a = (1440..<1490).map { Self.emitter(seed: 3).drops(at: Double($0)) }
        let b = (1440..<1490).map { Self.emitter(seed: 4).drops(at: Double($0)) }
        #expect(a != b)
    }

    @Test func dropsStayInTicksSquareAndFade() {
        // Around the head at any point in the stretch: inside the envelope, fading out by the end.
        let emitter = Self.emitter()
        let rig = TickRig(workout: WorkoutSamples.params(left: 100))
        for elapsed in stride(from: 1200.0, through: 1500, by: 0.1) {
            for drop in emitter.drops(at: elapsed) {
                let x = 50 + drop.at.x, y = rig.centerY + drop.at.y
                #expect(x >= 8 && x <= 96 && y >= 6 && y <= 98, "drop at \(x), \(y)")
                #expect((0...1).contains(drop.opacity))
            }
        }
    }

    @Test func theWorkoutShowsItsSweat() {
        let loops = WorkoutLoops(workout: TickWorkout(planned: 1500, endDate: Date(timeIntervalSinceReferenceDate: 1500),
                                                      pausedRemaining: nil, seed: 8))
        let date = Date(timeIntervalSinceReferenceDate: 1470)
        #expect(loops.frame(at: date).motion.sweat == loops.sweat.drops(at: 1470))
        #expect(loops.frame(at: Date(timeIntervalSinceReferenceDate: 600)).motion.sweat.isEmpty)
    }
}
