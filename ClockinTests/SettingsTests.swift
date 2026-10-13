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

    /// The length chips set the same preset; a session already running keeps its length.
    @Test func changingLengthMidSessionWaitsForTheNextOne() {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   settingsStore: InMemorySettingsStore(), now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false, liveActivity: SpyLiveActivity(),
                                   notifications: SpyNotifier(), widgets: SpyWidgets(), haptics: SpyHaptics(),
                                   announce: { _ in })
        services.engine.start(name: "Essay")
        #expect(services.engine.active?.plannedDuration == 1_500)

        services.settings.preset = .deep
        #expect(services.engine.active?.plannedDuration == 1_500)
        #expect(services.plan.focus == 3_000)
    }

    @Test func chipsReadTheirLengths() {
        #expect(Preset.classic.chipTitle == "25 min")
        #expect(Preset.deep.spokenSummary == "Deep, 50 minutes focus, 10 minutes break")
        #expect(SessionLength.custom(minutes: 35).chipTitle == "35 min")
        #expect(SessionLength.custom(minutes: 35).spokenSummary == "Custom, 35 minutes focus, 7 minutes break")
        #expect(SessionLength.custom(minutes: 35).detail == "35 min focus · 7 min break")
    }

    // MARK: Lengths set on the dial

    @Test func dialLengthsSnapToFiveAndToThePresets() {
        #expect(SessionLength(minutes: 35) == .custom(minutes: 35))
        #expect(SessionLength(minutes: 33) == .custom(minutes: 35))
        #expect(SessionLength(minutes: 2) == .custom(minutes: 5))
        #expect(SessionLength(minutes: 90) == .custom(minutes: 60))
        #expect(SessionLength(minutes: 15) == .preset(.short))
        #expect(SessionLength(minutes: 25) == .preset(.classic))
        #expect(SessionLength(minutes: 50) == .preset(.deep))
    }

    @Test func customBreaksAreAFifthAndTheyAgreeWithThePresets() {
        for preset in Preset.allCases {
            #expect(SessionLength.shortBreak(forFocusMinutes: Int(preset.focus / 60)) == preset.shortBreak)
        }
        #expect(SessionLength.custom(minutes: 5).shortBreak == 180)
        #expect(SessionLength.custom(minutes: 35).shortBreak == 420)
        #expect(SessionLength.custom(minutes: 60).shortBreak == 720)
    }

    @Test func aCustomLengthIsSavedAndAPresetReplacesIt() throws {
        let store = DefaultsSettingsStore(defaults: UserDefaults(suiteName: "clockin.tests.\(UUID())")!)
        var settings = TimerSettings(preset: .deep)
        settings.length = .custom(minutes: 35)
        store.save(settings)
        #expect(store.load().length == .custom(minutes: 35))
        #expect(store.load().plan == TimerPlan(focus: 2_100, shortBreak: 420, longBreak: 900))

        // The preset underneath is kept, and choosing one clears the custom length.
        #expect(store.load().preset == .deep)
        settings.length = .preset(.short)
        #expect(settings.customMinutes == nil)
        #expect(settings.plan.focus == 900)

        // Dragging onto a preset's length is that preset.
        settings.length = .custom(minutes: 25)
        #expect(settings.length == .preset(.classic))
        #expect(settings.customMinutes == nil)
    }

    @Test func customLengthsTheDialCouldNotSetAreIgnored() throws {
        #expect(try decode(#"{"preset":"deep"}"#).length == .preset(.deep))
        #expect(try decode(#"{"preset":"deep","customMinutes":35}"#).length == .custom(minutes: 35))
        #expect(try decode(#"{"preset":"deep","customMinutes":37}"#).length == .preset(.deep))
        #expect(try decode(#"{"preset":"deep","customMinutes":25}"#).length == .preset(.deep))
        #expect(try decode(#"{"preset":"deep","customMinutes":240}"#).length == .preset(.deep))
        #expect(try decode(#"{"preset":"deep","customMinutes":"long"}"#).length == .preset(.deep))
    }

    @Test func aDialLengthIsUsedFromTheNextSession() {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   settingsStore: InMemorySettingsStore(), now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false, liveActivity: SpyLiveActivity(),
                                   notifications: SpyNotifier(), widgets: SpyWidgets(), haptics: SpyHaptics(),
                                   announce: { _ in })
        services.engine.start(name: "Essay")
        services.settings.length = .custom(minutes: 40)
        #expect(services.engine.active?.plannedDuration == 1_500)

        services.engine.cancel()
        services.engine.start(name: "Essay")
        #expect(services.engine.active?.plannedDuration == 2_400)
        #expect(services.engine.active?.nextBreakSeconds == 480)
    }
}

/// Dragging the knob round the 60-minute face.
struct DialLengthTests {
    private let center = CGPoint(x: 100, y: 100)

    @Test func touchesMapToAnglesClockwiseFromTwelve() {
        #expect(DialLength.angle(of: CGPoint(x: 100, y: 0), around: center) == 0)
        #expect(abs(DialLength.angle(of: CGPoint(x: 200, y: 100), around: center) - .pi / 2) < 1e-9)
        #expect(abs(DialLength.angle(of: CGPoint(x: 100, y: 200), around: center) - .pi) < 1e-9)
        #expect(abs(DialLength.angle(of: CGPoint(x: 0, y: 100), around: center) - 3 * .pi / 2) < 1e-9)
    }

    @Test func anglesSnapToFiveMinutesWithinTheDial() {
        let quarter = Double.pi / 2
        #expect(DialLength.minutes(atAngle: quarter, previous: nil) == 15)
        #expect(DialLength.minutes(atAngle: quarter * 1.1, previous: nil) == 15)
        #expect(DialLength.minutes(atAngle: quarter * 2, previous: nil) == 30)
        #expect(DialLength.minutes(atAngle: 0.01, previous: nil) == 5)
        #expect(DialLength.minutes(atAngle: 2 * .pi - 0.01, previous: nil) == 60)
        #expect(DialLength.angle(forMinutes: 15) == quarter)
    }

    @Test func draggingPastTwelveHoldsAtTheEnd() {
        // Clockwise past 60 stays at 60; anticlockwise past 5 stays at 5.
        #expect(DialLength.minutes(atAngle: 0.2, previous: 60) == 60)
        #expect(DialLength.minutes(atAngle: 2 * .pi - 0.2, previous: 5) == 5)
        // A first touch can land anywhere.
        #expect(DialLength.minutes(atAngle: 2 * .pi - 0.2, previous: nil) == 60)
        // Ordinary steps follow the finger.
        #expect(DialLength.minutes(atAngle: DialLength.angle(forMinutes: 40), previous: 35) == 40)
    }

    @Test func theKnobSitsOnTheArcAtItsMinutes() {
        let top = DialLength.knobPoint(minutes: 60, side: 200)
        #expect(abs(top.x - 100) < 1e-9)
        #expect(abs(top.y - (100 - 66)) < 1e-9)
        let quarter = DialLength.knobPoint(minutes: 15, side: 200)
        #expect(abs(quarter.x - 166) < 1e-9)
        #expect(abs(quarter.y - 100) < 1e-9)
        // A finger-sized target on small dials, the knob's own size on big ones.
        #expect(DialLength.grabSize(side: 160) == 44)
        #expect(DialLength.grabSize(side: 400) == 64)
    }
}
