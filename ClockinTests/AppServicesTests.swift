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
    let widgets = SpyWidgets()
    let haptics = SpyHaptics()
    let announcer = SpyAnnouncer()

    func makeServices(historyUnavailable: Bool = false) -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), historyUnavailable: historyUnavailable,
                    stateStore: state, now: { [clock] in clock.now }, calendar: osloCalendar,
                    schedulesCompletion: false,
                    liveActivity: liveActivity, notifications: notifier, widgets: widgets, haptics: haptics,
                    announce: { [announcer] in announcer.spoken.append($0) })
    }

    func finishFocus(_ services: AppServices) {
        services.engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus))
        services.reconcile()
    }

    @Test func startShowsTheSessionEverywhere() {
        let services = makeServices()
        services.engine.start(name: "Essay")

        #expect(liveActivity.calls == ["sync"])
        #expect(liveActivity.lastBreakDuration == Durations.duration(for: .rest))
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
        #expect(announcer.spoken == ["Focus complete. Time for a break."])
    }

    @Test func movingOnFromACompletionClearsTheCard() {
        let services = makeServices()
        finishFocus(services)
        services.engine.skipBreak()

        #expect(liveActivity.calls.last == "endAll")
        #expect(notifier.calls.last == "cancel")
    }

    @Test func breakEndIsAnnouncedAndClearsTheCard() {
        let services = makeServices()
        finishFocus(services)
        services.engine.startBreak()
        clock.advance(Durations.duration(for: .rest))
        services.reconcile()

        #expect(services.engine.stage == .idle)
        #expect(liveActivity.calls.last == "endAll")
        #expect(announcer.spoken.last == "Break's over. Ready when you are.")
    }

    @Test func lateBreakEndIsNotAnnounced() {
        let services = makeServices()
        finishFocus(services)
        services.engine.startBreak()
        clock.advance(Durations.duration(for: .rest) + 3_600)
        services.reconcile()

        #expect(services.engine.stage == .idle)
        #expect(liveActivity.calls.last == "endAll")
        #expect(announcer.spoken == ["Focus complete. Time for a break."])
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
        clock.advance(Durations.duration(for: .focus) + 3_600)
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
        clock.advance(Durations.duration(for: .focus) + 60)
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
        #expect(snapshot.sessions.map(\.seconds) == [Durations.duration(for: .focus)])
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

        services.engine.undoCancel()
        #expect(liveActivity.calls == ["sync", "endAll", "sync"])
        #expect(notifier.calls == ["schedule", "cancel", "schedule"])
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
}
