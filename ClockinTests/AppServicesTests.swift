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
                    stateStore: state, now: { [clock] in clock.now }, schedulesCompletion: false,
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

        #expect(services.engine.stage == .focusComplete(name: "Essay"))
        #expect(state.state.pendingRecords?.map(\.name) == ["Essay"])
    }
}
