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
        // Nothing about the time changed, so nothing else hears of it.
        #expect(effects.events == events)
        #expect(engine.active?.endDate == clock.now.addingTimeInterval(Preset.classic.shortBreak - 70))
        // Saved, so a relaunch shows it.
        #expect(store.state.active?.breakStyle == .stretch)
        #expect(makeEngine().active?.breakStyle == .stretch)
    }

    @Test func choosingTheSameStyleKeepsWhenItStarted() {
        let engine = makeEngine(style: .stretch)
        onABreak(engine)
        clock.advance(30)
        engine.chooseBreakStyle(.stretch)
        #expect(engine.active?.breakStyleFrom == 0)
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
