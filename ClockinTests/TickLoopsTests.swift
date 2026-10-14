import Foundation
import Testing
@testable import Clockin

/// Tick's idle loops: random but repeatable blinks, calm breathing, and
/// each state's own motion.
struct TickLoopsTests {
    /// The times a Tick blinks in its first `seconds`.
    private func blinks(_ loops: TickLoops, over seconds: Double) -> [Double] {
        var starts: [Double] = []
        var t = 0.0, shut = false
        while t < seconds {
            let closed = loops.blink(at: t) > 0
            if closed && !shut { starts.append(t) }
            shut = closed
            t += 0.01
        }
        return starts
    }

    @Test func blinksComeThreeToSixSecondsApart() {
        let starts = blinks(TickLoops(pose: .ready, seed: 7), over: 60)
        #expect(starts.count >= 9)
        #expect((1.5...3.01).contains(starts[0]))
        for (a, b) in zip(starts, starts.dropFirst()) {
            #expect((2.99...6.2).contains(b - a))
        }
    }

    @Test func twoTicksDontBlinkTogether() {
        #expect(blinks(TickLoops(pose: .ready, seed: 1), over: 20) != blinks(TickLoops(pose: .ready, seed: 2), over: 20))
        // The same Tick blinks the same way every time.
        #expect(blinks(TickLoops(pose: .ready, seed: 1), over: 20) == blinks(TickLoops(pose: .ready, seed: 1), over: 20))
    }

    @Test(arguments: TickPose.allCases)
    func everyLoopStaysInRange(_ pose: TickPose) {
        let loops = TickLoops(pose: pose, seed: 3)
        for step in 0..<600 {
            let m = loops.motion(at: Double(step) * 0.05)
            #expect((0...1).contains(m.blink) && (0...1).contains(m.breath))
            #expect(abs(m.lean) <= 5.001 && (0...1).contains(m.hop))
        }
    }

    @Test func workingStaysCalm() {
        let loops = TickLoops(pose: .working, seed: 3)
        for step in 0..<300 {
            let m = loops.motion(at: Double(step) * 0.1)
            #expect(m.hop == 0 && m.lean == 0 && m.footTap == 0 && m.crownTap == 0 && m.shrug == 0)
        }
    }

    @Test func eachStateMovesItsOwnWay() {
        func ever(_ pose: TickPose, _ value: (TickMotion) -> Double) -> Bool {
            let loops = TickLoops(pose: pose, seed: 5)
            return (0..<400).contains { value(loops.motion(at: Double($0) * 0.05)) != 0 }
        }
        #expect(ever(.ready) { $0.crownTap })
        #expect(ever(.waiting) { $0.footTap } && ever(.waiting) { $0.browLift })
        #expect(ever(.ringing) { $0.lean } && ever(.ringing) { $0.alarmFlash })
        #expect(ever(.done) { $0.hop })
        #expect(ever(.onBreak) { $0.steam })
        #expect(ever(.streak) { $0.twinkle })
        #expect(ever(.sleeping) { $0.zeeRise })
        #expect(!ever(.working) { $0.crownTap })
    }

    @Test func theShrugHappensOnce() {
        let loops = TickLoops(pose: .interrupted, seed: 1)
        #expect(loops.motion(at: 0.7).shrug > 0.9)
        #expect(loops.motion(at: 3).shrug == 0)
        #expect(loops.motion(at: 30).shrug == 0)
    }

    @Test func breathingComesInShortSpells() {
        let loops = TickLoops(pose: .working, seed: 4)
        let samples = (0..<1600).map { loops.motion(at: Double($0) * 0.05).breath }
        let breathing = samples.filter { $0 > 0 }.count
        // Two 3.2 s breaths in every 16 s: about 40% of the time, never all of it.
        #expect(breathing > 400 && breathing < 800)
        // Between spells nothing moves until the next blink or breath.
        #expect(loops.nextMovement(from: 0) > 0)
    }

    @Test func ringingDoesntBreathe() {
        #expect(TickLoops(pose: .ringing, seed: 1).motion(at: 1.3).breath == 0)
    }
}
