import Foundation
import Testing
@testable import Clockin

/// Time kept after the bell: counted once a minute, capped, and added to
/// the saved session only when asked.
@MainActor
struct OvertimeTests {
    let clock = FakeClock()
    let store = InMemorySessionStateStore()
    let log = SpyLog()
    let effects = SpyEffects()

    func makeEngine() -> SessionEngine {
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar, store: store, log: log,
                                   schedulesCompletion: false)
        engine.effects = effects
        return engine
    }

    /// Starts a Classic session and lets it run out exactly now.
    func finishedEngine() -> SessionEngine {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        return engine
    }

    /// Dates are doubles, so seconds since the bell are compared loosely.
    func close(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
        value.map { abs($0 - expected) < 0.001 } ?? false
    }

    @Test func overtimeCountsFromTheBellOnly() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        #expect(engine.overtime(at: clock.now) == nil)
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        #expect(engine.overtime(at: clock.now) == 0)
        #expect(close(engine.overtime(at: clock.now.addingTimeInterval(61)), 61))
        #expect(close(engine.overtime(at: clock.now.addingTimeInterval(59 * 60)), 59 * 60))
    }

    @Test func overtimeStopsAtTheCap() {
        let engine = finishedEngine()
        #expect(engine.overtime(at: clock.now.addingTimeInterval(SessionEngine.maxOvertime)) != nil)
        #expect(engine.overtime(at: clock.now.addingTimeInterval(SessionEngine.maxOvertime + 1)) == nil)
    }

    @Test func aSessionEndedEarlyHasNoOvertime() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(600)
        engine.finishEarly()
        #expect(engine.stage.completedFocus?.outcome == .endedEarly)
        #expect(engine.overtime(at: clock.now.addingTimeInterval(300)) == nil)
        #expect(engine.overtimeChanges(after: clock.now).isEmpty)
    }

    @Test func keepingAddsWholeMinutesAndMovesTheEnd() throws {
        let engine = finishedEngine()
        let bell = clock.now
        clock.advance(3 * 60 + 40)
        engine.keepOvertime()

        let focus = try #require(engine.stage.completedFocus)
        #expect(focus.focusSeconds == Preset.classic.focus + 180)
        #expect(focus.completedAt == bell.addingTimeInterval(180))
        #expect(focus.keptOvertime == 180)
        #expect(log.recorded.count == 1)
        #expect(log.recorded.first?.focusSeconds == Preset.classic.focus + 180)
        #expect(log.recorded.first?.completedAt == bell.addingTimeInterval(180))
        #expect(effects.events.last == .overtimeKept)
        // Still a whole session that counts toward the set.
        #expect(focus.countsAsFull)
    }

    @Test func keepingHappensOnce() {
        let engine = finishedEngine()
        clock.advance(5 * 60)
        engine.keepOvertime()
        clock.advance(5 * 60)
        #expect(engine.overtime(at: clock.now) == nil)
        engine.keepOvertime()
        #expect(engine.stage.completedFocus?.focusSeconds == Preset.classic.focus + 300)
        #expect(effects.events.filter { $0 == .overtimeKept }.count == 1)
    }

    @Test func underAMinuteThereIsNothingToKeep() {
        let engine = finishedEngine()
        clock.advance(59)
        engine.keepOvertime()
        #expect(engine.stage.completedFocus?.keptOvertime == nil)
        #expect(log.recorded.first?.focusSeconds == Preset.classic.focus)
    }

    @Test func aSessionWaitingToBeSavedGetsTheOvertimeToo() {
        log.failing = true
        let engine = finishedEngine()
        clock.advance(4 * 60)
        engine.keepOvertime()
        #expect(engine.pendingRecords.count == 1)
        #expect(engine.pendingRecords.first?.focusSeconds == Preset.classic.focus + 240)

        log.failing = false
        engine.reconcile()
        #expect(engine.pendingRecords.isEmpty)
        #expect(log.recorded.first?.focusSeconds == Preset.classic.focus + 240)
    }

    @Test func aFailedUpdateIsRetriedLater() {
        let engine = finishedEngine()
        log.failing = true
        clock.advance(2 * 60)
        engine.keepOvertime()
        #expect(engine.pendingRecords.first?.keptOvertime == 120)

        log.failing = false
        engine.reconcile()
        #expect(engine.pendingRecords.isEmpty)
        #expect(log.recorded.count == 1)
        #expect(log.recorded.first?.focusSeconds == Preset.classic.focus + 120)
    }

    @Test func discardingLeavesTheSessionAsItRang() {
        let engine = finishedEngine()
        clock.advance(10 * 60)
        engine.startBreak()
        #expect(engine.active?.phase == .rest)
        #expect(log.recorded.first?.focusSeconds == Preset.classic.focus)
        #expect(engine.overtime(at: clock.now) == nil)
    }

    @Test func overtimeAndWhatWasKeptSurviveARelaunch() {
        let engine = finishedEngine()
        clock.advance(6 * 60)
        #expect(close(makeEngine().overtime(at: clock.now), 6 * 60))
        engine.keepOvertime()
        let relaunched = makeEngine()
        #expect(relaunched.stage.completedFocus?.keptOvertime == 360)
        #expect(relaunched.overtime(at: clock.now) == nil)
    }

    @Test func theScreenRedrawsOnWholeMinutesUntilTheCap() throws {
        let engine = finishedEngine()
        let bell = clock.now
        let changes = engine.overtimeChanges(after: bell.addingTimeInterval(90))
        #expect(changes.first == bell.addingTimeInterval(120))
        #expect(try #require(changes.last) > bell.addingTimeInterval(SessionEngine.maxOvertime))
        #expect(changes.count == 60)
    }

    @Test func aCompletionSavedByAnOlderBuildHasNoKeptOvertime() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Essay","startedAt":0,"completedAt":1500,"focusSeconds":1500}"#
        let focus = try JSONDecoder().decode(CompletedFocus.self, from: Data(json.utf8))
        #expect(focus.keptOvertime == nil)
    }

    @Test func theCardShowsMinutesBeyondThePlan() {
        let end = Date(timeIntervalSince1970: 1_760_000_000)
        let card = SessionSummary(id: UUID(), name: "Essay", startedAt: end.addingTimeInterval(-1680), completedAt: end,
                                  focusSeconds: 1680, plannedSeconds: 1500, outcome: .completed)
        #expect(card.rows.map(\.label) == ["Focused", "Planned", "Extra", "Ended", "Set of four"])
        #expect(card.rows.first { $0.label == "Extra" }?.value == "+3 min")
    }

    @Test func overtimeCopy() {
        #expect(Copy.overtimeShort(minutes: 3) == "+3 min")
        #expect(Copy.keepOvertime(minutes: 3) == "Keep +3 min")
        #expect(Copy.keptOvertime(minutes: 3) == "Kept 3 more min")
        #expect(Copy.overtimeSpoken(minutes: 1) == "1 minute over")
    }
}
