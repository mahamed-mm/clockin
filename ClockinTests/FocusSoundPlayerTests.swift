import Foundation
import Testing
@testable import Clockin

/// The focus sound's level over time.
struct FocusSoundEnvelopeTests {
    @Test func startFadesInAfterTheWindUp() {
        let envelope = FocusSoundEnvelope().fading(to: 1, at: 100, .startIn, bell: 100 + 1500)
        #expect(envelope.gain(at: 100) == 0)
        #expect(envelope.gain(at: 100.5) == 0)
        #expect(envelope.gain(at: 102) > 0.4 && envelope.gain(at: 102) < 0.6)
        #expect(envelope.gain(at: 103.5) == 1)
        #expect(envelope.gain(at: 1000) == 1)
    }

    @Test func itIsSilentASecondBeforeTheBell() {
        let bell: TimeInterval = 1600
        let envelope = FocusSoundEnvelope(from: 1, to: 1, start: 0, length: 0, bell: bell)
        #expect(envelope.gain(at: bell - 4) == 1)
        #expect(envelope.gain(at: bell - 2) > 0 && envelope.gain(at: bell - 2) < 1)
        #expect(envelope.gain(at: bell - 1) == 0)
        #expect(envelope.gain(at: bell) == 0)
        #expect(envelope.silentFrom == bell - 1)
    }

    @Test func pauseFadesOutFromWhereverItIs() {
        let playing = FocusSoundEnvelope().fading(to: 1, at: 0, .startIn, bell: 1500)
        // Paused halfway through the fade in: out from there, over a second.
        let paused = playing.fading(to: 0, at: 2, .pauseOut, bell: 1500)
        #expect(abs(paused.gain(at: 2) - playing.gain(at: 2)) < 0.0001)
        #expect(paused.gain(at: 3) == 0)
        #expect(paused.silentFrom == 3)

        let resumed = paused.fading(to: 1, at: 10, .resumeIn, bell: 1600)
        #expect(resumed.gain(at: 10) == 0)
        #expect(resumed.gain(at: 13) == 1)
    }

    @Test func cancelStopsQuickly() {
        let playing = FocusSoundEnvelope(from: 1, to: 1, start: 0, length: 0, bell: 1500)
        let stopped = playing.fading(to: 0, at: 50, .stopOut, bell: 1500)
        #expect(stopped.gain(at: 50) == 1)
        #expect(stopped.gain(at: 50.5) == 0)
    }

    @Test func extendingMovesTheBellsFade() {
        var envelope = FocusSoundEnvelope(from: 1, to: 1, start: 0, length: 0, bell: 1500)
        #expect(envelope.gain(at: 1499) == 0)
        envelope.bell = 1800
        #expect(envelope.gain(at: 1499) == 1)
        #expect(envelope.gain(at: 1799) == 0)
    }

    @Test func eachChangeHasItsFade() {
        #expect(FocusSoundFade.for(.started) == .startIn)
        #expect(FocusSoundFade.for(.resumed) == .resumeIn)
        #expect(FocusSoundFade.for(.paused) == .pauseOut)
        #expect(FocusSoundFade.for(.cancelled) == .stopOut)
        #expect(FocusSoundFade.for(.finishedEarly) == .stopOut)
        for silent: SessionEvent in [.focusCompleted(.live), .breakStarted, .breakSkipped, .breakFinished(.live),
                                     .completionDismissed] {
            #expect(FocusSoundFade.for(silent) == .now, "\(silent)")
        }
        #expect(FocusSoundFade.for(.historySaved) == nil)
    }
}

/// The focus sound follows the session, from the app or from outside it.
@MainActor
struct FocusSoundWiringTests {
    let clock = FakeClock()
    let player = SpyFocusSound()
    let sounds = SpySounds()

    func makeServices(sound: FocusSound = .rain) -> AppServices {
        var settings = TimerSettings()
        settings.focusSound = sound
        return AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                           settingsStore: InMemorySettingsStore(settings), now: { [clock] in clock.now },
                           calendar: osloCalendar, schedulesCompletion: false,
                           liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), alarm: SpyAlarm(),
                           widgets: SpyWidgets(), haptics: SpyHaptics(), sounds: sounds, focusSound: player,
                           isForeground: { true }, announce: { _ in })
    }

    @Test func aSessionPlaysItsSoundUntilTheBell() throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        let end = try #require(services.engine.active?.endDate)
        #expect(services.engine.active?.focusSound == .rain)
        #expect(player.calls.last == .init(cue: FocusSoundCue(sound: .rain, bell: end), fade: .startIn))

        services.engine.pause()
        #expect(player.calls.last == .init(cue: nil, fade: .pauseOut))
        clock.advance(60)
        services.engine.resume()
        let later = try #require(services.engine.active?.endDate)
        #expect(player.calls.last == .init(cue: FocusSoundCue(sound: .rain, bell: later), fade: .resumeIn))

        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(player.calls.last == .init(cue: nil, fade: .now))
    }

    @Test func breaksAreSilent() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        #expect(player.calls.last == .init(cue: nil, fade: .now))
    }

    @Test func cancelAndFinishNowStopIt() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.engine.cancel()
        #expect(player.calls.last == .init(cue: nil, fade: .stopOut))

        services.engine.start(name: "Essay")
        clock.advance(10 * 60)
        services.engine.finishEarly()
        #expect(player.calls.last == .init(cue: nil, fade: .stopOut))
    }

    @Test func offMeansNothingPlays() {
        let services = makeServices(sound: .off)
        services.engine.start(name: "Essay")
        #expect(services.engine.active?.focusSound == nil)
        #expect(player.calls.last == .init(cue: nil, fade: .startIn))
    }

    @Test func pickingASoundPlaysItAndRemembersIt() throws {
        let services = makeServices(sound: .off)
        services.engine.start(name: "Essay")
        services.chooseFocusSound(.fireplace)
        let end = try #require(services.engine.active?.endDate)
        #expect(services.engine.active?.focusSound == .fireplace)
        #expect(services.settings.focusSound == .fireplace)
        #expect(player.calls.last == .init(cue: FocusSoundCue(sound: .fireplace, bell: end), fade: .resumeIn,
                                           chosen: true))
        services.chooseFocusSound(.off)
        #expect(services.engine.active?.focusSound == nil)
        #expect(player.calls.last == .init(cue: nil, fade: .stopOut, chosen: true))
    }

    @Test func startedFromOutsideTheAppItStillAsksForTheSoundButMakesNoClick() async throws {
        let services = makeServices()
        _ = await services.intentStart(minutes: nil, name: "Essay")
        let end = try #require(services.engine.active?.endDate)
        #expect(player.calls.last == .init(cue: FocusSoundCue(sound: .rain, bell: end), fade: .startIn))
        #expect(sounds.played.isEmpty)
    }

    @Test func extendingMovesTheBell() throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus - 120)
        services.engine.extend()
        let end = try #require(services.engine.active?.endDate)
        #expect(player.calls.last == .init(cue: FocusSoundCue(sound: .rain, bell: end), fade: .resumeIn))
    }

    @Test func volumeAndMixingReachThePlayer() {
        let services = makeServices()
        services.settings.focusSoundVolume = 0.3
        services.settings.mixFocusSound = true
        #expect(player.volume == 0.3)
        #expect(player.mixes)
    }

    @Test func settingsFromOlderBuildsHaveNoSound() throws {
        let old = try JSONDecoder().decode(TimerSettings.self, from: Data(#"{"preset":"classic"}"#.utf8))
        #expect(old.focusSound == .off)
        #expect(old.focusSoundVolume == 0.6)
        #expect(!old.mixFocusSound)
        let unknown = try JSONDecoder().decode(TimerSettings.self,
                                               from: Data(#"{"focusSound":"whales","focusSoundVolume":7}"#.utf8))
        #expect(unknown.focusSound == .off)
        #expect(unknown.focusSoundVolume == 1)
    }

    @Test func aSessionWithASoundFromANewerBuildStillLoads() throws {
        var session = ActiveSession(id: UUID(), name: "Essay", phase: .focus, plannedDuration: 1500,
                                    focusStartedAt: clock.now, state: .running(endDate: clock.now + 1500))
        session.focusSound = .rain
        var json = String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
        json = json.replacingOccurrences(of: #""rain""#, with: #""whales""#)
        let decoded = try JSONDecoder().decode(ActiveSession.self, from: Data(json.utf8))
        #expect(decoded.focusSound == .off)
        #expect(decoded.name == "Essay")
    }
}

@MainActor
final class SpyFocusSound: FocusSoundPlaying {
    struct Call: Equatable {
        var cue: FocusSoundCue?
        var fade: FocusSoundFade
        var chosen = false
    }

    var calls: [Call] = []
    var volume = 0.0
    var mixes = false
    private(set) var state: FocusSoundState = .silent

    func follow(_ cue: FocusSoundCue?, fade: FocusSoundFade, chosen: Bool) {
        calls.append(Call(cue: cue, fade: fade, chosen: chosen))
        state = cue.map { .playing($0.sound) } ?? .silent
    }

    func configure(volume: Double, mixes: Bool) {
        self.volume = volume
        self.mixes = mixes
    }

    func retryIfWaiting() {}
}
