import Foundation
import Testing
@testable import Clockin

/// Tick catching a parked thought, or nodding mid-combo, and drawing only then.
struct TickCatchTests {
    @Test func handsGoUpCatchAndComeBackDown() {
        #expect(TickCatch.reach(at: 0) == 0)
        #expect(TickCatch.reach(at: 0.3) == 1)
        #expect(TickCatch.reach(at: 0.6) > 0 && TickCatch.reach(at: 0.6) < 1)
        #expect(TickCatch.reach(at: TickCatch.length) == 0)
        let caught = TickCatch.apply(to: TickMotion(), at: 0.3, nod: false)
        #expect(caught.catchReach == 1)
        #expect(caught.squash > 0)
        #expect(caught.bob == 0)
    }

    @Test func midComboItsJustANod() {
        let nod = TickCatch.apply(to: TickMotion(), at: TickCatch.nodLength / 2, nod: true)
        #expect(nod.bob > 2)
        #expect(nod.catchReach == 0)
    }

    @Test func beforeAndAfterNothingChanges() {
        #expect(TickCatch.apply(to: TickMotion(), at: -0.1, nod: false) == TickMotion())
        #expect(TickCatch.apply(to: TickMotion(), at: TickCatch.length, nod: false) == TickMotion())
        #expect(TickCatch.apply(to: TickMotion(), at: TickCatch.nodLength, nod: true) == TickMotion())
    }

    /// Frames through the catch, none in the quiet before it, and a wake-up
    /// at the moment it arrives.
    @Test func framesOnlyWhileItPlays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let catchAt = now.addingTimeInterval(4)
        // Sleeping Tick drifts; working Tick here only blinks: a quiet pose with seed 7.
        let loops = TickLoops(pose: .working, seed: 7, breathes: false)
        let schedule = TickLoopSchedule(loops: loops, since: now.addingTimeInterval(-60), pokedAt: nil,
                                        caughtAt: catchAt, paused: false, speed: 1)
        let dates = Array(schedule.entries(from: now, mode: .normal).prefix { $0 < now.addingTimeInterval(6) })
        #expect(dates.contains { abs($0.timeIntervalSince(catchAt)) < 0.001 }, "wakes when it arrives")
        let during = dates.filter { $0 >= catchAt && $0 < catchAt.addingTimeInterval(TickCatch.length) }
        #expect(during.count >= Int(TickCatch.length * 25), "\(during.count) frames through the catch")
        let without = TickLoopSchedule(loops: loops, since: now.addingTimeInterval(-60), pokedAt: nil,
                                       paused: false, speed: 1)
        let quiet = Array(without.entries(from: now, mode: .normal).prefix { $0 < now.addingTimeInterval(6) })
        #expect(dates.count >= quiet.count + during.count - 6)
        #expect(dates.count < quiet.count + 40)
    }
}
