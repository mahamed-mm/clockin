import Foundation
import Testing
@testable import Clockin

/// "Break's over" in the app: only after a break that ran to its end, for
/// a little while, gone the moment something else happens.
@MainActor
struct BreakOverTests {
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

    /// Focus done and its break under way.
    func onABreak(_ engine: SessionEngine, name: String = "Essay") {
        engine.start(name: name)
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        engine.startBreak()
    }

    func breakRunsOut(_ engine: SessionEngine) {
        clock.advance(Preset.classic.shortBreak)
        engine.reconcile()
    }

    @Test func aBreakThatRanOutSaysSo() throws {
        let engine = makeEngine()
        onABreak(engine)
        let end = clock.now.addingTimeInterval(Preset.classic.shortBreak)
        breakRunsOut(engine)
        let moment = try #require(engine.breakOver)
        #expect(moment == BreakOverMoment(endedAt: end, name: "Essay", wasLong: false))
        #expect(engine.stage == .idle)
        #expect(effects.events.last == .breakFinished(.live))
        // Saved, so a relaunch moments later still says so.
        #expect(store.state.breakOver == moment)
        #expect(makeEngine().breakOver == moment)
    }

    @Test func skippingOrMovingOnSaysNothing() {
        let engine = makeEngine()
        onABreak(engine)
        engine.skipBreak()
        #expect(engine.breakOver == nil)
        engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        engine.skipBreak()
        #expect(engine.stage == .idle && engine.breakOver == nil)
    }

    @Test func startingOrChoosingALengthPutsItAway() {
        let engine = makeEngine()
        onABreak(engine)
        breakRunsOut(engine)
        engine.dismissBreakOver()
        #expect(engine.breakOver == nil)
        #expect(store.state.breakOver == nil)

        onABreak(engine)
        breakRunsOut(engine)
        engine.start(name: "Essay")
        #expect(engine.breakOver == nil)
        #expect(store.state.breakOver == nil)
    }

    @Test func itLastsTenMinutes() {
        let engine = makeEngine()
        onABreak(engine)
        breakRunsOut(engine)
        let ended = clock.now
        #expect(engine.breakOverEnds == ended.addingTimeInterval(BreakOverMoment.window))
        clock.advance(9 * 60)
        engine.reconcile()
        #expect(engine.breakOver != nil)
        clock.advance(61)
        engine.reconcile()
        #expect(engine.breakOver == nil)
    }

    @Test func itEndsAtMidnight() throws {
        // A break that runs out at 23:55.
        let day = osloCalendar.startOfDay(for: clock.now)
        clock.now = day.addingTimeInterval(23 * 3600 + 55 * 60 - Preset.classic.focus - Preset.classic.shortBreak)
        let engine = makeEngine()
        onABreak(engine)
        breakRunsOut(engine)
        #expect(engine.breakOver != nil)
        #expect(engine.breakOverEnds == day.addingTimeInterval(24 * 3600))
        clock.advance(6 * 60)
        engine.reconcile()
        #expect(engine.breakOver == nil)
    }

    @Test func onlyARecentEndingShowsAfterARelaunch() {
        // A break that ran out while the app was closed.
        let engine = makeEngine()
        onABreak(engine)
        clock.advance(Preset.classic.shortBreak + 4 * 60)
        let relaunched = makeEngine()
        relaunched.reconcile()
        #expect(relaunched.breakOver?.endedAt == clock.now.addingTimeInterval(-4 * 60))
        #expect(effects.events.last == .breakFinished(.recent))

        onABreak(engine)
        clock.advance(Preset.classic.shortBreak + 30 * 60)
        let later = makeEngine()
        later.reconcile()
        #expect(later.breakOver == nil)
        // A moment saved, then opened long after, is dropped.
        let moment = BreakOverMoment(endedAt: clock.now.addingTimeInterval(-60), name: "", wasLong: false)
        store.state = PersistedSessionState(breakOver: moment)
        #expect(makeEngine().breakOver == moment)
        clock.advance(20 * 60)
        #expect(makeEngine().breakOver == nil)
    }

    @Test func theNextSessionIsCounted() {
        #expect(BreakOverMoment.nextPosition(fullToday: 2) == 3)
        // After the long break, a new set.
        #expect(BreakOverMoment.nextPosition(fullToday: 4) == 1)
        #expect(BreakOverMoment.nextPosition(fullToday: 0) == 1)
        #expect(Copy.nextSession(name: "Essay", position: 3, setSize: 4) == "Next: Essay · session 3 of 4")
        #expect(Copy.nextSession(name: "", position: 1, setSize: 4) == "Next: Focus session · session 1 of 4")
    }

    @Test func anOlderSavedStateHasNoMoment() throws {
        let state = try JSONDecoder().decode(PersistedSessionState.self, from: Data(#"{"format":3}"#.utf8))
        #expect(state.breakOver == nil)
    }

    // MARK: Tick

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func director(hour: Int = 14, since: TimeInterval = 0, until: TimeInterval?) -> TickDirector {
        TickDirector(stage: .idle, hour: hour, stageSince: now.addingTimeInterval(-since),
                     breakOverUntil: until.map { now.addingTimeInterval($0) })
    }

    @Test func tickIsReadyToGoBackToWork() {
        #expect(director(until: 300).pose(at: now) == .ready)
        #expect(director(until: 300).backToWork(at: now))
        // Ready even at night, while it lasts; then asleep as usual.
        #expect(director(hour: 23, until: 300).pose(at: now) == .ready)
        #expect(director(hour: 23, until: -1).pose(at: now) == .sleeping)
        #expect(!director(until: -1).backToWork(at: now))
        #expect(director(since: 60, until: 300).nextChange(after: now) == now.addingTimeInterval(300))
    }

    @Test func comingBackStretchesIn() {
        let loops = TickLoops(pose: .ready, seed: 1, entering: true, backToWork: true)
        #expect(loops.entryLength == StretchMove.backToWork.duration)
        #expect(TickLoops(pose: .ready, seed: 1, entering: false, backToWork: true).entryLength == 0)
        #expect(TickLoops(pose: .ready, seed: 1, entering: true).entryLength == 0)
    }

    @Test func theNextPillIsUpNextNotInProgress() {
        // VoiceOver reads the pills as a count; nothing is in progress yet.
        #expect(Copy.pillsSpoken(completed: 2, setSize: 4, inProgress: false) == "2 of 4 today")
    }
}
