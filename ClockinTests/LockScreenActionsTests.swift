import Foundation
import Testing
@testable import Clockin

/// The Lock Screen's actions at the end: Start break, Start focus, "+5 min".
@MainActor
struct LockScreenActionsTests {
    let clock = FakeClock()
    let live = SpyLiveActivity()
    let sounds = SpySounds()

    func makeServices() -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                    now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                    liveActivity: live, notifications: SpyNotifier(), alarm: SpyAlarm(),
                    widgets: SpyWidgets(), haptics: SpyHaptics(), sounds: sounds, announce: { _ in })
    }

    @Test func plusFiveShowsOnlyInTheLastFiveMinutes() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        #expect(live.lastCanExtend == false)
        clock.advance(Preset.classic.focus - 4 * 60)
        services.engine.pause()
        #expect(live.lastCanExtend == true)
        services.engine.resume()
        services.engine.extend()
        services.engine.extend()
        services.engine.extend()
        // Fifteen minutes is the most; the button goes.
        #expect(live.lastCanExtend == false)
    }

    @Test func plusFiveFromTheLockScreenAddsTimeQuietly() async throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        let session = try #require(services.engine.active)
        sounds.played = []

        await services.lockScreenExtend(sessionID: session.id)
        #expect(services.engine.active?.extendedSeconds == nil, "too early: nothing added")

        clock.advance(Preset.classic.focus - 2 * 60)
        await services.lockScreenExtend(sessionID: UUID())
        #expect(services.engine.active?.extendedSeconds == nil, "another session's card")

        await services.lockScreenExtend(sessionID: session.id)
        #expect(services.engine.active?.extendedSeconds == SessionEngine.extensionStep)
        #expect(sounds.played.isEmpty)
    }

    @Test func aFinishedFocusKeepsItsCardForStartBreak() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(live.calls.last == "done")
        services.reconcile()
        #expect(live.calls.last != "endAll", "kept while the break can still start")
    }

    @Test func aFinishedBreakSaysSoWithStartFocusThenGoes() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        clock.advance(Preset.classic.shortBreak)
        services.reconcile()
        #expect(live.calls.contains("breakDone"))
        #expect(live.calls.last != "endAll", "kept while Break's over shows")

        // Long after, the moment has passed and the card goes.
        clock.advance(60 * 60)
        services.engine.reconcile()
        services.reconcile()
        #expect(live.calls.last == "endAll")
    }

    @Test func theCardGoesWhenTheMomentDoes() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        clock.advance(Preset.classic.shortBreak)
        services.reconcile()
        #expect(live.calls.last == "breakDone")

        // Ten minutes on, with the app open: the screen's own timer reconciles.
        clock.advance(BreakOverMoment.window + 1)
        services.engine.reconcile()
        #expect(live.calls.last == "endAll")

        // Choosing a length puts it away too.
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        clock.advance(Preset.classic.shortBreak)
        services.reconcile()
        #expect(live.calls.last == "breakDone")
        services.engine.dismissBreakOver()
        #expect(live.calls.last == "endAll")
    }

    @Test func aFinishedCardSaysHowItEndedAndWhatsNext() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func state(_ phase: SessionPhase, completed: Int, long: Bool = false) -> FocusActivityAttributes.ContentState {
            var session = ActiveSession(id: UUID(), name: "Essay", phase: phase, plannedDuration: 300,
                                        focusStartedAt: start, state: .running(endDate: start.addingTimeInterval(300)))
            session.isLongBreak = long ? true : nil
            return .init(session: session, completedToday: completed, breakDuration: 300)
        }
        #expect(state(.rest, completed: 2).doneStatus == "Break's over")
        #expect(state(.rest, completed: 2).doneLine == "Next: session 3 of 4")
        // Without long breaks, four done is just session 1 of 4.
        #expect(state(.rest, completed: 4).doneLine == "Next: session 1 of 4")
        // After the long break, a new set.
        #expect(state(.rest, completed: 4, long: true).doneLine == "Next: new set")
        #expect(state(.focus, completed: 1).doneStatus == "Focus complete")
        #expect(state(.focus, completed: 1).doneLine == "Time for a 5-minute break.")
    }

    @Test func aBreakFoundLongAfterLeavesNoCard() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        clock.advance(6 * 60 * 60)
        services.reconcile()
        #expect(!live.calls.contains("breakDone"))
        #expect(live.calls.last == "endAll")
    }

    @Test func olderCardsLoadWithoutTheNewField() throws {
        let json = #"{"phase":"focus","plannedDuration":1500,"endDate":0}"#
        let state = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.canExtend == nil)
        // A break from before styles rests, and says so the old way.
        let rest = #"{"phase":"rest","plannedDuration":300,"endDate":0}"#
        let card = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: Data(rest.utf8))
        #expect(card.breakStyle == nil)
        #expect(card.phaseLabel == "Break")
    }
}

/// The Smart Stack's one button.
struct SmallFocusActionTests {
    @Test func oneButtonForWhatComesNext() {
        #expect(SmallFocusView.action(phase: .focus, done: false) == .pauseResume)
        #expect(SmallFocusView.action(phase: .rest, done: false) == .pauseResume)
        #expect(SmallFocusView.action(phase: .focus, done: true) == .startBreak)
        #expect(SmallFocusView.action(phase: .rest, done: true) == .startFocus)
    }
}
