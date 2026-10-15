import Foundation
import Testing
@testable import Clockin

/// Each engine event reaches the right side effects.
@MainActor
struct AppServicesTests {
    let clock = FakeClock()
    let state = InMemorySessionStateStore()
    let liveActivity = SpyLiveActivity()
    let notifier = SpyNotifier()
    let alarm = SpyAlarm()
    let widgets = SpyWidgets()
    let haptics = SpyHaptics()
    let announcer = SpyAnnouncer()

    func makeServices(historyUnavailable: Bool = false) -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), historyUnavailable: historyUnavailable,
                    stateStore: state, now: { [clock] in clock.now }, calendar: osloCalendar,
                    schedulesCompletion: false,
                    liveActivity: liveActivity, notifications: notifier, alarm: alarm, widgets: widgets,
                    haptics: haptics,
                    announce: { [announcer] in announcer.spoken.append($0) })
    }

    func finishFocus(_ services: AppServices) {
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
    }

    @Test func keptOvertimeReachesTheWidgetAndTheHistory() throws {
        let services = makeServices()
        finishFocus(services)
        clock.advance(4 * 60)
        let reloads = widgets.reloads
        services.engine.keepOvertime()

        #expect(widgets.reloads == reloads + 1)
        #expect(widgets.lastSnapshot?.sessions.first?.seconds == Preset.classic.focus + 240)
        #expect(services.lastEvent.event == .overtimeKept)
        #expect(services.lastEvent.feedback == .selection)
        let saved = try #require(try services.history?.allSessions().first)
        #expect(saved.focusSeconds == Preset.classic.focus + 240)
    }

    @Test func startShowsTheSessionEverywhere() {
        let services = makeServices()
        services.engine.start(name: "Essay")

        #expect(liveActivity.calls == ["sync"])
        #expect(liveActivity.lastBreakDuration == Preset.classic.shortBreak)
        #expect(notifier.calls == ["schedule"])
        #expect(widgets.reloads == 1)
    }

    @Test func pauseKeepsTheCardAndDropsTheAlert() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.engine.pause()

        #expect(liveActivity.calls == ["sync", "sync"])
        #expect(notifier.calls == ["schedule", "cancel"])
    }

    @Test func cancelClearsTheCardAndTheAlert() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.engine.cancel()

        #expect(liveActivity.calls == ["sync", "endAll"])
        #expect(notifier.calls == ["schedule", "cancel"])
    }

    @Test func completionCelebratesAndLeavesADoneCard() {
        let services = makeServices()
        finishFocus(services)

        #expect(liveActivity.calls == ["sync", "done"])
        #expect(notifier.calls == ["schedule"]) // Its alert is playing right now.
        #expect(haptics.plays == 1)
        #expect(services.celebrations == 1)
        #expect(announcer.spoken == ["Focus complete. Time for a 5-minute break."])
    }

    @Test func movingOnFromACompletionClearsTheCard() {
        let services = makeServices()
        finishFocus(services)
        services.engine.skipBreak()

        #expect(liveActivity.calls.last == "endAll")
        #expect(notifier.calls.last == "cancel")
    }

    @Test func breakEndIsAnnouncedAndTheCardOffersStartFocus() {
        let services = makeServices()
        finishFocus(services)
        services.engine.startBreak()
        clock.advance(Preset.classic.shortBreak)
        services.reconcile()

        #expect(services.engine.stage == .idle)
        #expect(liveActivity.calls.last == "breakDone")
        #expect(announcer.spoken.last == "Break's over. Ready when you are.")
    }

    @Test func aBreaksAlertSaysWhichSessionIsNext() {
        let services = makeServices()
        finishFocus(services)
        services.engine.startBreak()
        #expect(notifier.completedToday == 1)

        let rest = ActiveSession(id: UUID(), name: "Essay", phase: .rest, plannedDuration: 300,
                                 focusStartedAt: clock.now, state: .running(endDate: clock.now.addingTimeInterval(300)))
        let content = EndNotifier.content(for: rest, completedToday: 2)
        #expect(content.title == "Break's over")
        #expect(content.subtitle == "Next: Essay · session 3 of 4")
        #expect(content.body == "Ready when you are.")

        var long = rest
        long.isLongBreak = true
        #expect(EndNotifier.content(for: long, completedToday: 4).subtitle == "Next: Essay · new set")
    }

    @Test func lateBreakEndIsNotAnnounced() {
        let services = makeServices()
        finishFocus(services)
        services.engine.startBreak()
        clock.advance(Preset.classic.shortBreak + 3_600)
        services.reconcile()

        #expect(services.engine.stage == .idle)
        #expect(liveActivity.calls.last == "endAll")
        #expect(announcer.spoken == ["Focus complete. Time for a 5-minute break."])
    }

    @Test func savedWaitingSessionsReloadTheWidget() {
        let services = makeServices()
        services.sessionEngine(services.engine, didEmit: .historySaved)
        #expect(widgets.reloads == 1)
        #expect(liveActivity.calls.isEmpty && notifier.calls.isEmpty)
    }

    @Test func settleWaitsForAlertsAndLiveActivity() async {
        let services = makeServices()
        await services.settle()
        #expect(notifier.flushes == 1)
        #expect(liveActivity.flushes == 1)
    }

    @Test func idleLaunchClearsLeftoverCards() {
        let services = makeServices()
        services.restore()
        #expect(liveActivity.calls == ["endAll"])
    }

    @Test func launchMidSessionLeavesTheCardAlone() {
        makeServices().engine.start(name: "Essay")
        liveActivity.calls = []

        let relaunched = makeServices()
        relaunched.restore()
        #expect(liveActivity.calls == ["sync"])
    }

    @Test func staleCompletionOpensQuietly() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus + 3_600)
        services.reconcile()

        #expect(liveActivity.calls == ["sync", "done-quietly"])
        // Its alert went off long ago; it shouldn't linger in Notification Center.
        #expect(notifier.calls == ["schedule", "cancel"])
        #expect(haptics.plays == 0)
        #expect(services.celebrations == 0)
        #expect(announcer.spoken.isEmpty)
    }

    @Test func recentCompletionCelebratesWithoutSpeaking() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus + 60)
        services.reconcile()

        #expect(liveActivity.calls == ["sync", "done"])
        #expect(haptics.plays == 1)
        #expect(services.celebrations == 1)
        #expect(announcer.spoken.isEmpty)
    }

    @Test func eventsHandTheWidgetTodaysSessions() throws {
        let services = makeServices()
        finishFocus(services)

        let snapshot = try #require(widgets.lastSnapshot)
        #expect(snapshot.writtenAt == clock.now)
        #expect(snapshot.sessions.map(\.seconds) == [Preset.classic.focus])
    }

    @Test func launchWritesTheWidgetSnapshot() {
        let services = makeServices()
        services.restore()
        #expect(widgets.lastSnapshot?.sessions == [])
    }

    @Test func midnightMovesTodayAndRedrawsTheWidget() {
        clock.now = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 59))!
        let services = makeServices()
        #expect(osloCalendar.component(.day, from: services.today) == 9)

        clock.advance(120)
        services.timeChanged()
        #expect(osloCalendar.component(.day, from: services.today) == 10)
        #expect(widgets.reloads == 1)
    }

    @Test func dayThatTurnedOverWhileSuspendedIsCaughtOnReturn() {
        clock.now = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 59))!
        let services = makeServices()
        services.reconcile()
        #expect(widgets.reloads == 0)

        clock.advance(120)
        services.reconcile()
        #expect(osloCalendar.component(.day, from: services.today) == 10)
        #expect(widgets.reloads == 1)
    }

    @Test func clockChangeReaimsTheAlertAndTheCard() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        liveActivity.calls = []
        notifier.calls = []

        clock.advance(600) // The clock is set forward.
        services.timeChanged()
        #expect(liveActivity.calls == ["sync"])
        #expect(notifier.calls == ["schedule"])
    }

    @Test func repeatedLockScreenTapRedrawsTheCard() async throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        let id = try #require(services.engine.active?.id)
        await services.lockScreenSetPaused(true, sessionID: id)
        #expect(services.engine.active?.isPaused == true)
        liveActivity.calls = []

        await services.lockScreenSetPaused(true, sessionID: id)
        #expect(services.engine.active?.isPaused == true)
        #expect(liveActivity.calls == ["sync"])
        #expect(notifier.flushes == 2 && liveActivity.flushes == 2)
    }

    @Test func buttonOnALeftoverCardClearsItWhenIdle() async {
        let services = makeServices()
        await services.lockScreenSetPaused(true, sessionID: UUID())
        #expect(services.engine.stage == .idle)
        #expect(liveActivity.calls == ["endAll"])
    }

    @Test func undoBringsTheCardAndTheAlertBack() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.engine.cancel()
        #expect(announcer.spoken.last?.contains("Undo") == true)

        services.engine.undo()
        #expect(liveActivity.calls == ["sync", "endAll", "sync"])
        #expect(notifier.calls == ["schedule", "cancel", "schedule"])
    }

    @Test func undoingASkipBringsTheBreaksCardAndAlertBack() {
        let services = makeServices()
        finishFocus(services)
        services.engine.startBreak()
        liveActivity.calls = []
        notifier.calls = []
        services.engine.skipBreak()
        #expect(announcer.spoken.last?.contains("Undo") == true)

        services.engine.undo()
        #expect(services.engine.active?.phase == .rest)
        #expect(liveActivity.calls == ["endAll", "sync"])
        #expect(notifier.calls == ["cancel", "schedule"])
    }

    @Test func undoingDoneForNowLeavesTheLockScreenAlone() {
        let services = makeServices()
        finishFocus(services)
        services.engine.skipBreak()
        #expect(announcer.spoken.last?.contains("Undo") == true)
        liveActivity.calls = []
        notifier.calls = []

        services.engine.undo()
        #expect(services.engine.stage.completedFocus?.name == "Essay")
        #expect(liveActivity.calls.isEmpty)
        #expect(notifier.calls.isEmpty)
    }

    @Test func alertStatusFollowsPermissions() async {
        let services = makeServices()
        #expect(services.alertStatus == .unknown)

        notifier.status = .notDetermined
        await services.refreshAlertStatus()
        #expect(services.alertStatus == .notAsked)

        notifier.status = .denied
        await services.refreshAlertStatus()
        #expect(services.alertStatus == .notificationsOff)

        notifier.status = .authorized
        liveActivity.enabled = false
        await services.refreshAlertStatus()
        #expect(services.alertStatus == .liveActivitiesOff)

        liveActivity.enabled = true
        await services.refreshAlertStatus()
        #expect(services.alertStatus == .ready)
    }

    @Test func unopenableStoreKeepsFinishedSessionsPending() {
        let services = makeServices(historyUnavailable: true)
        finishFocus(services)

        #expect(services.engine.stage.completedFocus?.name == "Essay")
        #expect(state.state.pendingRecords?.map(\.name) == ["Essay"])
        // The waiting session still counts on the Lock Screen.
        #expect(liveActivity.lastCompletedToday == 1)
    }

    // MARK: The end alarm

    func ringing() -> AppServices {
        let services = makeServices()
        services.settings.ringAtEnd = true
        return services
    }

    @Test func withoutRingTheNotificationIsTheAlert() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        #expect(notifier.calls == ["schedule"])
        #expect(alarm.calls == ["cancel"])
    }

    @Test func ringingSetsTheAlarmInsteadOfTheNotification() {
        let services = ringing()
        services.engine.start(name: "Essay")
        #expect(alarm.calls == ["schedule"])
        #expect(notifier.calls == ["cancel"])

        services.engine.pause()
        #expect(alarm.calls == ["schedule", "cancel"])
        services.engine.resume()
        #expect(alarm.calls == ["schedule", "cancel", "schedule"])
        services.engine.cancel()
        #expect(alarm.calls.last == "cancel")
        services.engine.undo()
        #expect(alarm.calls.last == "schedule")
    }

    @Test func plusFiveMovesTheAlarm() {
        let services = ringing()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus - 60)
        services.engine.extend()
        #expect(alarm.calls == ["schedule", "schedule"])
    }

    @Test func aRingingAlarmStopsOnlyWhenSomeoneActs() {
        let services = ringing()
        finishFocus(services)
        // Live, and noticed a little later: it keeps ringing.
        #expect(alarm.calls == ["schedule"])

        // Starting the break stops it and sets one for the break's end.
        services.engine.startBreak()
        #expect(alarm.calls == ["schedule", "schedule"])

        // The break's alarm rings on into the idle screen; the next Start
        // replaces it with one for the new session.
        clock.advance(Preset.classic.shortBreak)
        services.reconcile()
        #expect(alarm.calls == ["schedule", "schedule"])
        services.engine.start(name: "Essay")
        #expect(alarm.calls == ["schedule", "schedule", "schedule"])
    }

    @Test func doneForNowSilencesIt() {
        let services = ringing()
        finishFocus(services)
        services.engine.skipBreak()
        #expect(alarm.calls == ["schedule", "cancel"])
    }

    @Test func aRecentCompletionKeepsRinging() {
        let services = ringing()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus + 60)
        services.reconcile()
        #expect(alarm.calls == ["schedule"])
    }

    @Test func aCompletionFromLongAgoGoesQuiet() {
        let services = ringing()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus + 3_600)
        services.reconcile()
        #expect(alarm.calls == ["schedule", "cancel"])
    }

    @Test func finishingEarlyNeverRings() {
        let services = ringing()
        services.engine.start(name: "Essay")
        clock.advance(600)
        services.engine.finishEarly()
        #expect(alarm.calls == ["schedule", "cancel"])
    }

    @Test func turningRingOnAsksOnceAndMovesTheRunningAlert() async {
        let services = makeServices()
        services.engine.start(name: "Essay")
        alarm.permission = .notDetermined
        alarm.calls = []
        notifier.calls = []

        await services.setRingAtEnd(true)
        #expect(alarm.calls == ["ask", "schedule"])
        #expect(notifier.calls == ["cancel"])
        #expect(services.alertStatus == .ready)

        await services.setRingAtEnd(false)
        #expect(alarm.calls.last == "cancel")
        #expect(notifier.calls.last == "schedule")
    }

    @Test func aDeniedAlarmFallsBackToTheNotification() async {
        let services = makeServices()
        alarm.permission = .notDetermined
        alarm.answer = .denied
        await services.setRingAtEnd(true)
        #expect(services.alertStatus == .alarmsOff)

        services.engine.start(name: "Essay")
        #expect(notifier.calls.last == "schedule")
        #expect(alarm.calls.last == "cancel")
    }

    @Test func startBreakOnTheAlarmStartsThatSessionsBreak() async throws {
        let services = ringing()
        finishFocus(services)
        let focus = try #require(services.engine.stage.completedFocus)

        await services.alarmStartBreak(after: UUID())
        #expect(services.engine.stage.completedFocus != nil)

        await services.alarmStartBreak(after: focus.id)
        #expect(services.engine.active?.phase == .rest)
        #expect(alarm.calls.last == "schedule")
        #expect(alarm.flushes == 2)
    }

    @Test func launchingIdleClearsAnAlarmLeftBehind() {
        let services = ringing()
        services.restore()
        #expect(alarm.calls == ["cancel"])
    }
}
