import Foundation
import Testing
@testable import Clockin

/// How a break is spent: chosen in Settings, changed for one break on the
/// break screen, and kept across a relaunch.
@MainActor
struct BreakStyleTests {
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

    /// Runs a focus session out and starts its break.
    func onABreak(_ engine: SessionEngine) {
        engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        engine.startBreak()
    }

    @Test func aBreakStartsTheWaySettingsSay() {
        let engine = makeEngine(style: .breathe)
        onABreak(engine)
        #expect(engine.active?.breakStyle == .breathe)
        #expect(engine.active?.breakStyleFrom == 0)
    }

    @Test func choosingChangesThisBreakFromNow() {
        let engine = makeEngine()
        onABreak(engine)
        let events = effects.events
        clock.advance(70)
        engine.chooseBreakStyle(.stretch)
        #expect(engine.active?.breakStyle == .stretch)
        #expect(engine.active?.breakStyleFrom == 70)
        // Nothing about the time changed; only that the style did, for the Lock Screen.
        #expect(effects.events == events + [.breakStyleChanged])
        #expect(engine.active?.endDate == clock.now.addingTimeInterval(Preset.classic.shortBreak - 70))
        // Saved, so a relaunch shows it.
        #expect(store.state.active?.breakStyle == .stretch)
        #expect(makeEngine().active?.breakStyle == .stretch)
    }

    @Test func choosingTheSameStyleKeepsWhenItStarted() {
        let engine = makeEngine(style: .stretch)
        onABreak(engine)
        clock.advance(30)
        let events = effects.events
        engine.chooseBreakStyle(.stretch)
        #expect(engine.active?.breakStyleFrom == 0)
        #expect(effects.events == events)
    }

    @Test func outsideTheAppABreakIsNamedWithItsStyle() {
        #expect(Copy.breakLabel(style: nil, isLong: false) == "Break")
        #expect(Copy.breakLabel(style: .rest, isLong: false) == "Break")
        #expect(Copy.breakLabel(style: .stretch, isLong: false) == "Break · Stretch")
        #expect(Copy.breakLabel(style: .breathe, isLong: false) == "Break · Breathe")
        #expect(Copy.breakLabel(style: nil, isLong: true) == "Long break")
        #expect(Copy.breakLabel(style: .rest, isLong: true) == "Long break")
        #expect(Copy.breakLabel(style: .stretch, isLong: true) == "Long break · Stretch")
        #expect(Copy.breakLabel(style: .breathe, isLong: true) == "Long break · Breathe")
    }

    @Test func theLockScreenAndTheWidgetsNameTheBreakAlike() throws {
        let engine = makeEngine(style: .breathe)
        onABreak(engine)
        let session = try #require(engine.active)
        let card = FocusActivityAttributes.ContentState(session: session)
        #expect(card.breakStyle == .breathe)
        #expect(card.phaseLabel == "Break · Breathe")
        #expect(card.phaseLabel == session.breakLabel)
        let line = LockScreenLine(stats: TodayStats(focusSeconds: 0, sessionCount: 1), active: session,
                                  symbol: "flask.fill", at: clock.now)
        #expect(line == .running(name: "Break · Breathe", symbol: SessionPhase.rest.symbol, phase: .rest,
                                 end: try #require(session.endDate)))
    }

    @Test func focusHasNoBreakStyleOnTheCard() throws {
        let engine = makeEngine(style: .stretch)
        engine.start(name: "Essay")
        let session = try #require(engine.active)
        #expect(session.breakLabel == nil)
        #expect(FocusActivityAttributes.ContentState(session: session).breakStyle == nil)
        #expect(FocusActivityAttributes.ContentState(session: session).phaseLabel == "Focus")
    }

    @Test func aPausedBreakCountsOnlyItsOwnTime() {
        let engine = makeEngine()
        onABreak(engine)
        clock.advance(40)
        engine.pause()
        clock.advance(600)
        engine.chooseBreakStyle(.breathe)
        #expect(engine.active?.breakStyleFrom == 40)
    }

    @Test func onlyABreakHasAStyle() {
        let engine = makeEngine(style: .stretch)
        engine.chooseBreakStyle(.breathe)
        #expect(engine.stage == .idle)
        engine.start(name: "Essay")
        engine.chooseBreakStyle(.breathe)
        #expect(engine.active?.breakStyle == nil)
        clock.advance(Preset.classic.focus)
        engine.reconcile()
        engine.chooseBreakStyle(.breathe)
        #expect(engine.stage.completedFocus != nil)
    }

    @Test func stretchingNeedsTimeForAStretch() {
        let engine = makeEngine()
        onABreak(engine)
        clock.advance(Preset.classic.shortBreak - StretchRoutine.minimumLength + 1)
        engine.chooseBreakStyle(.stretch)
        #expect(engine.active?.breakStyle == .rest)
        // Breathing fits any time left.
        engine.chooseBreakStyle(.breathe)
        #expect(engine.active?.breakStyle == .breathe)
    }

    @Test func aBreakTooShortToStretchStartsAsARest() {
        let engine = makeEngine(style: .stretch)
        engine.plan = { TimerPlan.classic.asTestTimers() }
        engine.start(name: "Essay")
        clock.advance(10)
        engine.reconcile()
        engine.startBreak()
        #expect(engine.active?.phase == .rest)
        #expect(engine.active?.breakStyle == .rest)
    }

    @Test func settingsFallBackToRest() throws {
        func decode(_ json: String) throws -> TimerSettings {
            try JSONDecoder().decode(TimerSettings.self, from: Data(json.utf8))
        }
        #expect(try decode(#"{"preset":"deep"}"#).duringBreaks == .rest)
        #expect(try decode(#"{"duringBreaks":"nap"}"#).duringBreaks == .rest)
        #expect(try decode(#"{"duringBreaks":"breathe"}"#).duringBreaks == .breathe)
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let settingsStore = DefaultsSettingsStore(defaults: defaults)
        var settings = TimerSettings()
        settings.duringBreaks = .stretch
        settingsStore.save(settings)
        #expect(settingsStore.load().duringBreaks == .stretch)
    }

    @Test func aSavedBreakFromAnotherBuildStillLoads() throws {
        func decode(_ json: String) throws -> PersistedSessionState {
            try JSONDecoder().decode(PersistedSessionState.self, from: Data(json.utf8))
        }
        // Before break styles: no style, which is a rest.
        let older = try #require(try decode(SessionStateCompatibilityTests.pausedBreak).active)
        #expect(older.breakStyle == nil && older.breakStyleFrom == nil)
        // A style this build doesn't know is a rest, and the session still loads.
        let newer = #"{"active":{"focusStartedAt":800000000,"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"","phase":"rest","plannedDuration":300,"state":{"running":{"endDate":800000300}},"breakStyle":"yoga","breakStyleFrom":12}}"#
        let session = try #require(try decode(newer).active)
        #expect(session.breakStyle == .rest)
        #expect(session.breakStyleFrom == 12)
    }
}
