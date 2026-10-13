import Foundation
import Testing
@testable import Clockin

/// Settings load whatever another build wrote, and a session keeps the
/// lengths it started with.
@MainActor
struct SettingsTests {
    let clock = FakeClock()

    private func decode(_ json: String) throws -> TimerSettings {
        try JSONDecoder().decode(TimerSettings.self, from: Data(json.utf8))
    }

    @Test func settingsRoundTripThroughDefaults() {
        let store = DefaultsSettingsStore(defaults: UserDefaults(suiteName: "clockin.tests.\(UUID())")!)
        #expect(store.load() == TimerSettings())

        store.save(TimerSettings(preset: .deep))
        #expect(store.load().preset == .deep)
    }

    @Test func missingOrUnknownValuesFallBackToClassic() throws {
        #expect(try decode("{}") == TimerSettings(preset: .classic, longBreak: true))
        #expect(try decode(#"{"longBreak":false}"#).longBreak == false)
        #expect(try decode(#"{"preset":"marathon"}"#).preset == .classic)
        #expect(try decode(#"{"preset":"short","somethingNew":true}"#).preset == .short)
    }

    @Test func appearanceAndSidewaysDefaultToTheSystemAndOn() throws {
        // What M3 and M4 builds saved.
        let older = try decode(#"{"preset":"deep","longBreak":false}"#)
        #expect(older.appearance == .system)
        #expect(older.bedsideWhenSideways)
        #expect(older.preset == .deep)
        #expect(try decode(#"{"appearance":"sepia"}"#).appearance == .system)
    }

    @Test func appearanceAndSidewaysAreSaved() {
        let store = DefaultsSettingsStore(defaults: UserDefaults(suiteName: "clockin.tests.\(UUID())")!)
        store.save(TimerSettings(appearance: .dark, bedsideWhenSideways: false))
        #expect(store.load().appearance == .dark)
        #expect(!store.load().bedsideWhenSideways)
    }

    @Test func appearanceMapsToAColorScheme() {
        #expect(Appearance.system.colorScheme == nil)
        #expect(Appearance.light.colorScheme == .light)
        #expect(Appearance.dark.colorScheme == .dark)
    }

    @Test func presetsHaveTheirLengths() {
        #expect(TimerSettings(preset: .classic).plan == TimerPlan(focus: 1_500, shortBreak: 300, longBreak: 900))
        #expect(TimerSettings(preset: .deep).plan == TimerPlan(focus: 3_000, shortBreak: 600, longBreak: 900))
        #expect(TimerSettings(preset: .short, longBreak: false).plan == TimerPlan(focus: 900, shortBreak: 180))
    }

    @Test func aSessionUsesThePlanItStartedWith() {
        var plan = TimerPlan(focus: 3_000, shortBreak: 600, longBreak: 900)
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar,
                                   store: InMemorySessionStateStore(), log: SpyLog(), schedulesCompletion: false)
        engine.plan = { plan }

        engine.start(name: "Thesis")
        #expect(engine.active?.plannedDuration == 3_000)
        #expect(engine.active?.nextBreakSeconds == 600)

        // Switching presets mid-session changes nothing in flight.
        plan = .classic
        clock.advance(3_000)
        engine.reconcile()
        #expect(engine.stage.completedFocus?.focusSeconds == 3_000)
        #expect(engine.stage.completedFocus?.breakSeconds == 600)

        engine.startBreak()
        #expect(engine.active?.plannedDuration == 600)

        // The next session picks up the new choice.
        engine.skipBreak()
        engine.start(name: "Thesis")
        #expect(engine.active?.plannedDuration == 1_500)
    }

    @Test func aDeepCompletionStaysRecentForItsLongerBreak() throws {
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar,
                                   store: InMemorySessionStateStore(), log: SpyLog(), schedulesCompletion: false)
        engine.plan = { TimerSettings(preset: .deep).plan }
        engine.start(name: "Thesis")
        clock.advance(3_000)
        engine.reconcile()
        let focus = try #require(engine.stage.completedFocus)

        #expect(engine.freshness(of: focus, at: clock.now.addingTimeInterval(500)) == .recent)
        #expect(engine.freshness(of: focus, at: clock.now.addingTimeInterval(700)) == .stale)
    }

    @Test func choosingAPresetIsSavedAndUsed() {
        let store = InMemorySettingsStore()
        let liveActivity = SpyLiveActivity()
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   settingsStore: store, now: { [clock] in clock.now }, calendar: osloCalendar,
                                   schedulesCompletion: false, liveActivity: liveActivity,
                                   notifications: SpyNotifier(), widgets: SpyWidgets(), haptics: SpyHaptics(),
                                   announce: { _ in })
        services.settings.preset = .short
        #expect(store.settings.preset == .short)

        services.engine.start(name: "Essay")
        #expect(services.engine.active?.plannedDuration == 900)
        #expect(liveActivity.lastBreakDuration == 180)
    }
}
