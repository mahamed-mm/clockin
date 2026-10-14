import Foundation
import Testing
@testable import Clockin

/// Siri, Shortcuts and the control: each does the honest thing for where the
/// session stands, and waits for its side effects before returning.
@MainActor
struct IntentTests {
    let clock = FakeClock()
    let state = InMemorySessionStateStore()
    let liveActivity = SpyLiveActivity()
    let notifier = SpyNotifier()
    let alarm = SpyAlarm()

    func makeServices() -> AppServices {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: state,
                                   now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: liveActivity, notifications: notifier, alarm: alarm,
                                   widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
        services.lastSessionName = { "Thesis" }
        return services
    }

    @Test func startUsesTheDialsLengthAndTheLastName() async {
        let services = makeServices()
        let outcome = await services.intentStart(minutes: nil, name: nil)
        #expect(outcome == .started(focus: Preset.classic.focus))
        #expect(services.engine.active?.name == "Thesis")
        #expect(notifier.flushes == 1)
        #expect(liveActivity.flushes == 1)
    }

    @Test func startWithMinutesIsForThisSessionOnly() async {
        let services = makeServices()
        let outcome = await services.intentStart(minutes: 40, name: "Essay")
        #expect(outcome == .started(focus: 40 * 60))
        #expect(services.engine.active?.plannedDuration == TimeInterval(40 * 60))
        #expect(services.engine.active?.breaks?.short == TimeInterval(8 * 60))
        #expect(services.engine.active?.name == "Essay")
        #expect(services.settings.length == .preset(.classic))
    }

    @Test func oddMinutesSnapToTheDial() async {
        let services = makeServices()
        _ = await services.intentStart(minutes: 12, name: nil)
        #expect(services.engine.active?.plannedDuration == TimeInterval(10 * 60))
        services.engine.cancel()
        _ = await services.intentStart(minutes: 90, name: nil)
        #expect(services.engine.active?.plannedDuration == TimeInterval(60 * 60))
    }

    @Test func startWhileRunningChangesNothing() async {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(600)
        let outcome = await services.intentStart(minutes: 50, name: "Other")
        #expect(outcome == .alreadyRunning(phase: .focus, remaining: Preset.classic.focus - 600))
        #expect(services.engine.active?.name == "Essay")
    }

    @Test func pauseAndResume() async {
        let services = makeServices()
        #expect(await services.intentPause() == .nothingRunning)
        services.engine.start(name: "Essay")
        clock.advance(300)
        #expect(await services.intentPause() == .paused(remaining: Preset.classic.focus - 300))
        #expect(services.engine.active?.isPaused == true)
        clock.advance(999)
        #expect(await services.intentResume() == .resumed(remaining: Preset.classic.focus - 300))
        #expect(services.engine.active?.isPaused == false)
        #expect(notifier.calls == ["schedule", "cancel", "schedule"])
    }

    @Test func stopKeepsTheMinutesDone() async throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(14 * 60)
        #expect(await services.intentStop() == .finished(kept: 14 * 60))
        let focus = try #require(services.engine.stage.completedFocus)
        #expect(focus.outcome == .endedEarly)
        #expect(notifier.calls.last == "cancel")
    }

    @Test func stopInTheFirstMinuteCancels() async {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(30)
        #expect(await services.intentStop() == .cancelled)
        #expect(services.engine.stage == .idle)
        #expect(services.engine.undoableCancel != nil)
    }

    @Test func stopEndsABreakAndPutsAwayACompletion() async {
        let services = makeServices()
        services.settings.ringAtEnd = true
        alarm.permission = .authorized
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        // The alarm is ringing; stopping puts the completion away and silences it.
        #expect(await services.intentStop() == .dismissed)
        #expect(services.engine.stage == .idle)
        #expect(alarm.calls.last == "cancel")

        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        #expect(await services.intentStop() == .breakEnded)
        #expect(services.engine.stage == .idle)
        #expect(await services.intentStop() == .nothingRunning)
    }

    @Test func theControlDoesWhatTheBigButtonWould() async {
        let services = makeServices()
        #expect(await services.intentPrimary() == .started(focus: Preset.classic.focus))
        clock.advance(60)
        #expect(await services.intentPrimary() == .paused(remaining: Preset.classic.focus - 60))
        #expect(await services.intentPrimary() == .resumed(remaining: Preset.classic.focus - 60))
        clock.advance(Preset.classic.focus)
        // Ran out while the app slept: the control catches up and starts the break.
        #expect(await services.intentPrimary() == .breakStarted(Preset.classic.shortBreak))
        #expect(services.engine.active?.phase == .rest)
    }

    @Test func controlFaceFollowsTheSavedState() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func session(_ state: ActiveSession.RunState, phase: SessionPhase = .focus) -> ActiveSession {
            ActiveSession(id: UUID(), name: "Essay", phase: phase, plannedDuration: 1500,
                          focusStartedAt: now.addingTimeInterval(-600), state: state)
        }
        #expect(ControlFace(state: PersistedSessionState(), now: now).action == .start)
        #expect(ControlFace(state: PersistedSessionState(active: session(.running(endDate: now.addingTimeInterval(60)))),
                            now: now).action == .pause)
        #expect(ControlFace(state: PersistedSessionState(active: session(.paused(remaining: 60))), now: now).action
                == .resume)
        #expect(ControlFace(state: PersistedSessionState(active: session(.running(endDate: now.addingTimeInterval(-1)))),
                            now: now).action == .startBreak)
        #expect(ControlFace(state: PersistedSessionState(active: session(.running(endDate: now.addingTimeInterval(-1)),
                                                                          phase: .rest)),
                            now: now).action == .start)
        let done = CompletedFocus(id: UUID(), name: "Essay", startedAt: now.addingTimeInterval(-1500), completedAt: now,
                                  focusSeconds: 1500)
        #expect(ControlFace(state: PersistedSessionState(completedFocus: done), now: now).action == .startBreak)
    }

    @Test func dialogs() {
        #expect(IntentOutcome.started(focus: 1500).dialog == "Focusing for 25 minutes.")
        #expect(IntentOutcome.paused(remaining: 720).dialog == "Paused. 12 minutes left.")
        #expect(IntentOutcome.finished(kept: 840).dialog == "Stopped. 14 minutes of focus kept.")
    }

    #if compiler(>=6.4)
    @Test func aSessionReadsAsSirisTimer() throws {
        guard #available(iOS 27, *) else { return }
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var session = ActiveSession(id: UUID(), name: "Essay", phase: .focus, plannedDuration: 1500,
                                    focusStartedAt: now.addingTimeInterval(-600),
                                    state: .running(endDate: now.addingTimeInterval(900)))
        var timer = FocusTimerEntity(session, now: now)
        #expect(timer.id == session.id)
        #expect(timer.duration == .seconds(1500))
        #expect(timer.durationRemaining == .seconds(900))
        #expect(timer.label == "Essay")
        #expect(timer.state == .running)

        session.state = .paused(remaining: 300)
        timer = FocusTimerEntity(session, now: now)
        #expect(timer.state == .paused)
        session.state = .running(endDate: now.addingTimeInterval(-1))
        #expect(FocusTimerEntity(session, now: now).state == .firing)
    }
    #endif
}
