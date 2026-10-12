import Foundation
import Testing
@testable import Clockin

/// "+5 min" near the end of focus, and "Finish now" that keeps the minutes.
@MainActor
struct FocusControlsTests {
    let clock = FakeClock()
    let log = SpyLog()
    let effects = SpyEffects()

    func makeEngine() -> SessionEngine {
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar,
                                   store: InMemorySessionStateStore(), log: log, schedulesCompletion: false)
        engine.effects = effects
        return engine
    }

    // MARK: +5 min

    @Test func plusFiveIsOfferedOnlyInTheLastFiveMinutes() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        #expect(!engine.canExtend(at: clock.now))
        clock.advance(1_199)
        #expect(!engine.canExtend(at: clock.now))
        clock.advance(1)
        #expect(engine.canExtend(at: clock.now))
    }

    @Test func plusFiveAddsFiveMinutesToARunningSession() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(1_400)
        engine.extend()

        let session = try #require(engine.active)
        #expect(session.plannedDuration == 1_800)
        #expect(session.remaining(at: clock.now) == 400)
        #expect(session.originalPlan == 1_500)
        #expect(effects.events.last == .extended)

        // A longer plan isn't mistaken for the clock being set back.
        engine.reconcile()
        #expect(engine.active?.remaining(at: clock.now) == 400)
    }

    @Test func plusFiveWorksWhilePaused() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(1_400)
        engine.pause()
        engine.extend()
        #expect(engine.active?.state == .paused(remaining: 400))
    }

    @Test func plusFiveStopsAtFifteenMinutes() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(1_400)
        engine.extend()
        // With more than five minutes left again, it waits.
        #expect(!engine.canExtend(at: clock.now))
        for _ in 1...3 {
            clock.advance(300)
            engine.extend()
        }
        #expect(engine.active?.extendedSeconds == 900)
        #expect(engine.active?.remaining(at: clock.now) == 100)
        #expect(!engine.canExtend(at: clock.now))
    }

    @Test func plusFiveIsntOfferedOnABreak() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(1_500)
        engine.reconcile()
        engine.startBreak()
        #expect(!engine.canExtend(at: clock.now))
    }

    @Test func anExtendedSessionRecordsItsFullLengthAndItsPlan() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(1_400)
        engine.extend()
        clock.advance(400)
        engine.reconcile()

        let focus = try #require(log.recorded.first)
        #expect(focus.focusSeconds == 1_800)
        #expect(focus.plannedSeconds == 1_500)
        #expect(focus.outcome == .completed)
    }

    // MARK: Finish now

    @Test func finishNowOpensAfterTheFirstMinute() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(59)
        #expect(!engine.canFinishEarly(at: clock.now))
        engine.finishEarly()
        #expect(engine.active != nil)

        clock.advance(1)
        #expect(engine.canFinishEarly(at: clock.now))
    }

    @Test func finishNowKeepsTheMinutesButNotThePause() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(600)
        engine.pause()
        clock.advance(3_600)
        engine.resume()
        clock.advance(120.6)
        engine.finishEarly()

        let focus = try #require(log.recorded.first)
        #expect(focus.focusSeconds == 720)
        #expect(focus.plannedSeconds == 1_500)
        #expect(focus.outcome == .endedEarly)
        #expect(focus.completedAt == clock.now)
        #expect(!focus.countsAsFull)
        #expect(engine.stage.completedFocus?.id == focus.id)
        #expect(effects.events.last == .finishedEarly)
    }

    @Test func finishingPastHalfwayFillsAPill() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(800)
        engine.finishEarly()
        #expect(try #require(log.recorded.first).countsAsFull)
    }

    @Test func finishNowOnATimerThatRanOutCompletesIt() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(1_600)
        engine.finishEarly()

        let focus = try #require(log.recorded.first)
        #expect(focus.outcome == .completed)
        #expect(focus.focusSeconds == 1_500)
        #expect(effects.events.last == .focusCompleted(.recent))
    }

    @Test func finishingEarlyIsQuiet() {
        let liveActivity = SpyLiveActivity()
        let notifier = SpyNotifier()
        let haptics = SpyHaptics()
        let announcer = SpyAnnouncer()
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: liveActivity, notifications: notifier, widgets: SpyWidgets(),
                                   haptics: haptics, announce: { [announcer] in announcer.spoken.append($0) })
        services.engine.start(name: "Essay")
        clock.advance(600)
        services.engine.finishEarly()

        #expect(liveActivity.calls == ["sync", "done-quietly"])
        #expect(notifier.calls == ["schedule", "cancel"])
        #expect(haptics.plays == 0)
        #expect(services.celebrations == 0)
        #expect(announcer.spoken == ["Ended early. Time for a 5-minute break."])
    }

    @Test func plusFiveReAimsTheAlertAndTheCard() {
        let liveActivity = SpyLiveActivity()
        let notifier = SpyNotifier()
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: liveActivity, notifications: notifier, widgets: SpyWidgets(),
                                   haptics: SpyHaptics(), announce: { _ in })
        services.engine.start(name: "Essay")
        clock.advance(1_400)
        services.engine.extend()

        #expect(liveActivity.calls == ["sync", "sync"])
        #expect(notifier.calls == ["schedule", "schedule"])
    }
}
