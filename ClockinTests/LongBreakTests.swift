import Foundation
import Testing
@testable import Clockin

/// Every fourth full session of the day earns the long break.
@MainActor
struct LongBreakTests {
    let clock = FakeClock()
    let log = SpyLog()

    func makeEngine(plan: TimerPlan = .classic) -> SessionEngine {
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar,
                                   store: InMemorySessionStateStore(), log: log, schedulesCompletion: false)
        engine.plan = { plan }
        return engine
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Runs one focus session to its end and moves on without a break.
    @discardableResult
    func finishFocus(_ engine: SessionEngine) -> CompletedFocus? {
        engine.start(name: "Essay")
        clock.advance(engine.active?.plannedDuration ?? 0)
        engine.reconcile()
        let focus = engine.stage.completedFocus
        engine.skipBreak()
        return focus
    }

    @Test func theFourthFullSessionEarnsTheLongBreak() {
        clock.now = at(9, 9)
        let engine = makeEngine()
        let breaks = (1...8).map { _ in finishFocus(engine)?.breakSeconds }
        #expect(breaks == [300, 300, 300, 900, 300, 300, 300, 900])
    }

    @Test func theLongBreakIsLongAndSaysSo() {
        clock.now = at(9, 9)
        let engine = makeEngine()
        for _ in 1...3 { finishFocus(engine) }

        engine.start(name: "Essay")
        #expect(engine.active?.nextBreakSeconds == 900)
        clock.advance(1_500)
        engine.reconcile()
        #expect(engine.stage.completedFocus?.isLongBreak == true)

        engine.startBreak()
        #expect(engine.active?.plannedDuration == 900)
        #expect(engine.active?.isLongBreak == true)
    }

    @Test func withLongBreaksOffEveryBreakIsShort() {
        clock.now = at(9, 9)
        let engine = makeEngine(plan: TimerPlan(focus: 1_500, shortBreak: 300))
        let breaks = (1...4).map { _ in finishFocus(engine)?.breakSeconds }
        #expect(breaks == [300, 300, 300, 300])
    }

    @Test func theSetStartsOverAtMidnight() {
        clock.now = at(9, 21)
        let engine = makeEngine()
        for _ in 1...3 { finishFocus(engine) }

        clock.now = at(10, 0, 5)
        #expect(finishFocus(engine)?.breakSeconds == 300)
    }

    @Test func sessionsWaitingToBeSavedCount() {
        clock.now = at(9, 9)
        let engine = makeEngine()
        log.failing = true
        for _ in 1...3 { finishFocus(engine) }
        #expect(engine.pendingRecords.count == 3)

        #expect(finishFocus(engine)?.breakSeconds == 900)
    }

    @Test func aCompletionFoundTheNextMorningCountsOnItsOwnDay() {
        clock.now = at(9, 21)
        let engine = makeEngine()
        for _ in 1...3 { finishFocus(engine) }

        clock.now = at(9, 23)
        engine.start(name: "Late one")
        clock.now = at(10, 8)
        engine.reconcile()
        #expect(engine.stage.completedFocus?.breakSeconds == 900)
    }

    @Test func anEarlyFinishUnderHalfDoesNotMoveTheSetOn() {
        clock.now = at(9, 14)
        for hour in 9...11 {
            log.recorded.append(CompletedFocus(id: UUID(), name: "Full", startedAt: at(9, hour),
                                               completedAt: at(9, hour, 25), focusSeconds: 1_500))
        }
        log.recorded.append(CompletedFocus(id: UUID(), name: "Short", startedAt: at(9, 12),
                                           completedAt: at(9, 12, 5), focusSeconds: 300,
                                           plannedSeconds: 1_500, outcome: .endedEarly))
        #expect(finishFocus(makeEngine())?.breakSeconds == 900)
    }

    @Test func theBreakIsSettledWhenTheSessionEnds() {
        clock.now = at(9, 9)
        let engine = makeEngine()
        for _ in 1...3 { finishFocus(engine) }

        engine.start(name: "Essay")
        #expect(engine.active?.nextBreakSeconds == 900)
        // One of the three is deleted from History meanwhile.
        log.recorded.removeFirst()
        clock.advance(1_500)
        engine.reconcile()
        #expect(engine.stage.completedFocus?.breakSeconds == 300)
    }

    @Test func aLongBreakCompletionStaysRecentForItsLength() throws {
        clock.now = at(9, 9)
        let engine = makeEngine()
        for _ in 1...3 { finishFocus(engine) }
        engine.start(name: "Essay")
        clock.advance(1_500)
        engine.reconcile()
        let focus = try #require(engine.stage.completedFocus)

        #expect(engine.freshness(of: focus, at: clock.now.addingTimeInterval(800)) == .recent)
        #expect(engine.freshness(of: focus, at: clock.now.addingTimeInterval(1_000)) == .stale)
    }

    @Test func theLockScreenNamesTheLongBreak() {
        clock.now = at(9, 9)
        let liveActivity = SpyLiveActivity()
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: liveActivity, notifications: SpyNotifier(), widgets: SpyWidgets(),
                                   haptics: SpyHaptics(), announce: { _ in })
        for _ in 1...3 { finishFocus(services.engine) }

        services.engine.start(name: "Essay")
        #expect(liveActivity.lastBreakDuration == 900)
        clock.advance(1_500)
        services.reconcile()
        #expect(liveActivity.calls.last == "done")
        #expect(liveActivity.lastBreakDuration == 900)
    }
}
