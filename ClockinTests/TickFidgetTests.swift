import Foundation
import Testing
@testable import Clockin

/// Ready Tick's fidgets: seeded, uneven, and drawn only while they play.
struct TickFidgetTests {
    func entries(_ schedule: FidgetSchedule, upTo end: TimeInterval) -> [FidgetSchedule.Entry] {
        var list: [FidgetSchedule.Entry] = []
        var t: TimeInterval = 0
        while true {
            let entry = schedule.entry(from: t)
            guard entry.start < end else { break }
            list.append(entry)
            t = entry.end
        }
        return list
    }

    @Test func theSameSeedFidgetsTheSameWay() {
        let a = entries(FidgetSchedule(seed: 12.5), upTo: 600)
        #expect(a == entries(FidgetSchedule(seed: 12.5), upTo: 600))
        #expect(a != entries(FidgetSchedule(seed: 40), upTo: 600))
    }

    @Test(arguments: [0.0, 3.3, 17, 58.1, 99.9])
    func gapsAreUnevenAndEightToTwentySeconds(_ seed: Double) {
        let list = entries(FidgetSchedule(seed: seed), upTo: 600)
        #expect(list.count >= 25)
        let gaps = zip(list, list.dropFirst()).map { $1.start - $0.end }
        #expect(gaps.allSatisfy { $0 >= 8 - 0.001 && $0 <= 20 + 0.001 })
        #expect(Set(gaps.map { Int($0) }).count > 4, "uneven")
        #expect(zip(list, list.dropFirst()).allSatisfy { $0.fidget != $1.fidget }, "never one twice in a row")
        #expect(Set(list.map(\.fidget)).count >= 4)
    }

    @Test func yawnsOnlyLateInTheDay() {
        #expect(!entries(FidgetSchedule(seed: 5), upTo: 1200).contains { $0.fidget == .yawn })
        #expect(entries(FidgetSchedule(seed: 5, yawns: true), upTo: 1200).contains { $0.fidget == .yawn })
    }

    @Test func readyMovesOnlyDuringAFidgetBlinkOrBreath() {
        let loops = TickLoops(pose: .ready, seed: 21, breathes: false)
        let list = entries(loops.fidgets, upTo: 120)
        // Between fidgets, the next movement is a blink or the next fidget, never now.
        for (entry, next) in zip(list, list.dropFirst()) {
            let between = entry.end + 0.5
            guard between < next.start - 0.5 else { continue }
            let move = loops.nextMovement(from: between)
            let blinking = loops.blink(at: move) > 0 || move == between && loops.blink(at: between) > 0
            #expect(move == next.start || blinking || move > between, "\(between) → \(move)")
            #expect(loops.motion(at: between).crownTap == 0)
            #expect(loops.motion(at: between).lookX == 0)
        }
        // During one, it moves.
        let first = list[0]
        #expect(loops.nextMovement(from: first.start + 0.1) == first.start + 0.1)
        let mid = loops.motion(at: first.start + first.fidget.length / 2)
        #expect(mid != TickMotion(blink: mid.blink, breath: mid.breath))
    }

    @Test func eachFidgetMovesSomethingAndEndsStill() {
        for fidget in TickFidget.allCases {
            var middle = TickMotion(), end = TickMotion()
            fidget.apply(fidget.length / 2, to: &middle)
            fidget.apply(fidget.length, to: &end)
            #expect(middle != TickMotion(), "\(fidget)")
            #expect(abs(end.crownTap) < 0.01 && abs(end.lookX) < 0.01 && abs(end.catchReach) < 0.01, "\(fidget)")
        }
    }
}
