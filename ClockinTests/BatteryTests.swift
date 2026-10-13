import Foundation
import SwiftUI
import Testing
@testable import Clockin

/// Screens redraw only when something on them changes.
@MainActor
struct TickScheduleTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000.4)

    func dates(_ schedule: TickSchedule, mode: TimelineScheduleMode = .normal, count: Int = 10) -> [Date] {
        Array(schedule.entries(from: start, mode: mode).prefix(count))
    }

    @Test func aRunningCountdownTicksOnWholeSecondsBeforeItsEnd() {
        let end = start.addingTimeInterval(3.7)
        let ticks = dates(TickSchedule(countdownEnd: end))
        #expect(ticks.first == start)
        #expect(ticks.dropFirst().map { end.timeIntervalSince($0) } == [3, 2, 1, 0])
    }

    @Test func nothingRunningMeansOneDrawing() {
        #expect(dates(TickSchedule()) == [start])
        #expect(dates(TickSchedule(countdownEnd: start.addingTimeInterval(-5))) == [start])
    }

    @Test func wakeDatesAreHonouredInOrder() {
        let later = start.addingTimeInterval(90)
        let sooner = start.addingTimeInterval(30)
        let past = start.addingTimeInterval(-30)
        #expect(dates(TickSchedule(wakeDates: [later, past, sooner])) == [start, sooner, later])
    }

    @Test func wakeDatesMixWithTicks() {
        let end = start.addingTimeInterval(2.7)
        let wake = start.addingTimeInterval(1.1)
        let ticks = dates(TickSchedule(countdownEnd: end, wakeDates: [wake]))
        #expect(ticks == [start, end.addingTimeInterval(-2), wake, end.addingTimeInterval(-1), end])
    }

    @Test func lowFrequencyTicksOncePerMinute() {
        let end = start.addingTimeInterval(150)
        let ticks = dates(TickSchedule(countdownEnd: end), mode: .lowFrequency)
        #expect(ticks.dropFirst().map { end.timeIntervalSince($0) } == [120, 60, 0])
        let slow = dates(TickSchedule(countdownEnd: end, interval: 60))
        #expect(slow == ticks)
    }
}

@MainActor
struct ControlChangeTests {
    let clock = FakeClock()

    func makeEngine() -> SessionEngine {
        SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar, store: InMemorySessionStateStore(),
                      log: SpyLog(), schedulesCompletion: false)
    }

    @Test func aRunningFocusChangesWhenFinishNowAndPlusFiveOpenAndAtTheEnd() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        let start = clock.now
        let changes = engine.controlChanges(after: start)
        #expect(changes == [start.addingTimeInterval(60), start.addingTimeInterval(1_200), start.addingTimeInterval(1_500)])

        // Each date is exactly when the control flips.
        #expect(!engine.canFinishEarly(at: changes[0].addingTimeInterval(-0.01)))
        #expect(engine.canFinishEarly(at: changes[0]))
        #expect(!engine.canExtend(at: changes[1].addingTimeInterval(-0.01)))
        #expect(engine.canExtend(at: changes[1]))
    }

    @Test func onlyFutureChangesAreListed() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(600)
        #expect(engine.controlChanges(after: clock.now).count == 2)
    }

    @Test func nothingChangesWhilePausedOrOnABreak() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        engine.pause()
        #expect(engine.controlChanges(after: clock.now).isEmpty)
        engine.resume()
        clock.advance(1_500)
        engine.reconcile()
        engine.startBreak()
        #expect(engine.controlChanges(after: clock.now).isEmpty)
    }
}

@MainActor
struct PowerStateTests {
    @Test func lowPowerOrHeatConstrains() {
        #expect(!PowerState.isConstrained(lowPowerMode: false, thermalState: .nominal))
        #expect(!PowerState.isConstrained(lowPowerMode: false, thermalState: .fair))
        #expect(PowerState.isConstrained(lowPowerMode: false, thermalState: .serious))
        #expect(PowerState.isConstrained(lowPowerMode: false, thermalState: .critical))
        #expect(PowerState.isConstrained(lowPowerMode: true, thermalState: .nominal))
    }

    @Test func refreshPicksUpAChange() {
        var lowPower = false
        let power = PowerState(read: { lowPower })
        #expect(!power.isConstrained)
        lowPower = true
        power.refresh()
        #expect(power.isConstrained)
    }
}
