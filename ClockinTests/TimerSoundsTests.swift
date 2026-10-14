import Foundation
import Testing
@testable import Clockin

/// Which change plays which kitchen-timer sound, and when there's none.
@MainActor
struct TimerSoundsTests {
    let clock = FakeClock()
    let sounds = SpySounds()
    let state = InMemorySessionStateStore()

    func makeServices(foreground: Bool = true, soundsOn: Bool = true) -> AppServices {
        var settings = TimerSettings()
        settings.timerSounds = soundsOn
        return AppServices(container: AppServices.makeEmptyContainer(), stateStore: state,
                           settingsStore: InMemorySettingsStore(settings), now: { [clock] in clock.now },
                           calendar: osloCalendar, schedulesCompletion: false,
                           liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), alarm: SpyAlarm(),
                           widgets: SpyWidgets(), haptics: SpyHaptics(), sounds: sounds,
                           isForeground: { foreground }, announce: { _ in })
    }

    @Test func eachChangeHasItsSound() {
        #expect(TimerSound.for(.started) == .windUp)
        #expect(TimerSound.for(.breakStarted) == .windUp)
        #expect(TimerSound.for(.paused) == .clunk)
        #expect(TimerSound.for(.resumed) == .click)
        // The end has the chime; letting go of a session is quiet.
        for quiet: SessionEvent in [.focusCompleted(.live), .breakFinished(.live), .cancelled, .breakSkipped,
                                    .completionDismissed, .restored, .extended, .finishedEarly, .overtimeKept,
                                    .historySaved] {
            #expect(TimerSound.for(quiet) == nil, "\(quiet)")
        }
    }

    @Test func theAppSoundsLikeAKitchenTimer() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.engine.pause()
        services.engine.resume()
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        services.engine.skipBreak()
        #expect(sounds.played == [.windUp, .clunk, .click, .windUp])
        services.playRatchet()
        #expect(sounds.played.last == .ratchet)
    }

    @Test func offInSettingsOrInTheBackgroundItsQuiet() {
        let off = makeServices(soundsOn: false)
        off.engine.start(name: "Essay")
        off.playRatchet()
        #expect(sounds.played.isEmpty)

        let background = makeServices(foreground: false)
        background.engine.start(name: "Essay")
        background.engine.pause()
        background.playRatchet()
        #expect(sounds.played.isEmpty)
    }

    @Test func siriShortcutsAndTheLockScreenAreQuiet() async {
        let services = makeServices()
        _ = await services.intentStart(minutes: nil, name: "Essay")
        _ = await services.intentPause()
        _ = await services.intentResume()
        await services.lockScreenSetPaused(true, sessionID: nil)
        await services.lockScreenSetPaused(false, sessionID: nil)
        _ = await services.intentPrimary()
        _ = await services.intentStop()
        clock.advance(Preset.classic.focus)
        services.engine.start(name: "Essay")
        services.reconcile()
        #expect(sounds.played == [.windUp])
        sounds.played = []
        clock.advance(Preset.classic.focus)
        services.reconcile()
        await services.alarmStartBreak(after: nil)
        #expect(sounds.played.isEmpty)
        // And afterwards the app's own taps sound again.
        services.engine.pause()
        #expect(sounds.played == [.clunk])
    }

    @Test func soundsAreOnUnlessTurnedOff() throws {
        func decode(_ json: String) throws -> TimerSettings {
            try JSONDecoder().decode(TimerSettings.self, from: Data(json.utf8))
        }
        #expect(try decode("{}").timerSounds)
        #expect(try decode(#"{"timerSounds":false}"#).timerSounds == false)
        #expect(try decode(#"{"timerSounds":"loud"}"#).timerSounds)
    }

    @Test func everySoundShips() {
        for sound in TimerSound.allCases {
            #expect(Bundle(for: AppServices.self).url(forResource: sound.fileName, withExtension: "caf") != nil, "\(sound)")
        }
    }
}
