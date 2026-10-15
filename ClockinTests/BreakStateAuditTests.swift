import Foundation
import Testing
@testable import Clockin

/// The break from end to end: asked for when focus ends, spent one way until
/// changed, ended early without touching History, and when it runs out,
/// naming the session that comes next.
@MainActor
struct BreakStateAuditTests {
    let clock = FakeClock()
    let store = InMemorySessionStateStore()
    let log = SpyLog()
    let effects = SpyEffects()

    func makeEngine(style: BreakStyle = .rest) -> SessionEngine {
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar, store: store, log: log,
                                   schedulesCompletion: false)
        engine.effects = effects
        engine.breakStyle = { style }
        return engine
    }

    /// Focus done and its break under way.
    func onABreak(_ engine: SessionEngine, name: String = "Essay") {
        engine.start(name: name)
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        engine.startBreak()
    }

    /// Lets the break under way run to its end.
    func breakRunsOut(_ engine: SessionEngine) {
        clock.advance(engine.active?.plannedDuration ?? 0)
        engine.reconcile()
    }

    /// Sessions that fill a pill today, as the app counts them for "Next".
    var fullToday: Int { log.recorded.filter(\.countsAsFull).count }

    // MARK: Focus end

    @Test func focusEndAsksBeforeTheBreak() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        // No break yet: the finished session waits to be moved on from.
        let focus = try #require(engine.stage.completedFocus)
        #expect(focus.name == "Essay")
        #expect(engine.active == nil)
        #expect(effects.events.last == .focusCompleted(.live))
        // Still waiting a minute later.
        clock.advance(60)
        engine.reconcile()
        #expect(engine.stage.completedFocus == focus)

        engine.startBreak()
        let rest = try #require(engine.active)
        #expect(rest.phase == .rest)
        #expect(rest.name == "Essay")
        #expect(rest.afterFocusID == focus.id)
        #expect(rest.endDate == clock.now.addingTimeInterval(Preset.classic.shortBreak))
        #expect(effects.events.last == .breakStarted)
    }

    // MARK: Break styles

    @Test func aBreakKeepsItsStyleUntilChanged() throws {
        let engine = makeEngine(style: .rest)
        onABreak(engine)
        let end = try #require(engine.active?.endDate)
        #expect(engine.active?.breakStyle == .rest)
        // Nothing moves it on by itself.
        clock.advance(30)
        engine.reconcile()
        #expect(engine.active?.breakStyle == .rest)

        clock.advance(30)
        engine.chooseBreakStyle(.stretch)
        #expect(engine.active?.breakStyle == .stretch)
        #expect(engine.active?.breakStyleFrom == 60)

        clock.advance(60)
        engine.chooseBreakStyle(.breathe)
        #expect(engine.active?.breakStyle == .breathe)
        #expect(engine.active?.breakStyleFrom == 120)
        // The break ends when it always would have.
        #expect(engine.active?.endDate == end)
        #expect(effects.events.filter { $0 == .breakStyleChanged }.count == 2)
    }

    // MARK: Ending early

    @Test func endingABreakEarlyKeepsTheFocusInHistory() throws {
        let engine = makeEngine()
        onABreak(engine)
        clock.advance(60)
        engine.skipBreak()
        #expect(engine.stage == .idle)
        #expect(engine.breakOver == nil)
        #expect(effects.events.last == .breakSkipped)

        let saved = try #require(log.recorded.first)
        #expect(log.recorded.count == 1)
        #expect(saved.name == "Essay")
        #expect(saved.focusSeconds == Preset.classic.focus)
        #expect(saved.outcome == .completed)

        // Once Undo has gone, the session is still saved, once.
        clock.advance(engine.undoWindow() + 1)
        engine.undo()
        engine.reconcile()
        #expect(engine.stage == .idle)
        #expect(log.recorded == [saved])
    }

    @Test func endingABreakEarlyAfterFinishingEarlyKeepsTheMinutesDone() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Preset.classic.focus / 2)
        engine.finishEarly()
        engine.startBreak()
        engine.skipBreak()
        #expect(engine.stage == .idle)

        let saved = try #require(log.recorded.first)
        #expect(log.recorded.count == 1)
        #expect(saved.outcome == .endedEarly)
        #expect(saved.focusSeconds == Preset.classic.focus / 2)
    }

    // MARK: Break's over

    @Test func anEndedBreakNamesTheNextSession() throws {
        let engine = makeEngine()
        onABreak(engine)
        let end = clock.now.addingTimeInterval(Preset.classic.shortBreak)
        breakRunsOut(engine)
        let moment = try #require(engine.breakOver)
        #expect(moment == BreakOverMoment(endedAt: end, name: "Essay", wasLong: false))
        #expect(engine.stage == .idle)
        #expect(effects.events.last == .breakFinished(.live))

        #expect(fullToday == 1)
        #expect(BreakOverMoment.nextLine(name: moment.name, fullToday: fullToday, afterLong: moment.wasLong)
                == "Next: Essay · session 2 of 4")
        #expect(BreakOverMoment.nextCardLine(fullToday: fullToday, afterLong: moment.wasLong)
                == "Next: session 2 of 4")
    }

    @Test func afterTheLongBreakTheNextSessionStartsANewSet() throws {
        // Morning, so the whole set falls on one day.
        clock.now = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9))!
        let engine = makeEngine()
        for _ in 1...3 {
            engine.start(name: "Essay")
            clock.advance(Preset.classic.focus)
            engine.reconcile()
            engine.skipBreak()
        }
        onABreak(engine)
        #expect(engine.active?.isLongBreak == true)
        breakRunsOut(engine)

        let moment = try #require(engine.breakOver)
        #expect(moment.wasLong)
        #expect(moment.name == "Essay")
        #expect(fullToday == 4)
        #expect(BreakOverMoment.nextLine(name: moment.name, fullToday: fullToday, afterLong: moment.wasLong)
                == "Next: Essay · new set")
        #expect(BreakOverMoment.nextCardLine(fullToday: fullToday, afterLong: moment.wasLong) == "Next: new set")
    }
}
