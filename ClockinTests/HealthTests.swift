import Foundation
import Testing
@testable import Clockin

/// Mindful Minutes: written only when chosen and allowed, kept in step with
/// History, and never written twice.
@MainActor
struct HealthTests {
    let clock = FakeClock()
    let state = InMemorySessionStateStore()
    let mindful = SpyMindful()

    func makeServices(saveToHealth: Bool = true) -> AppServices {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: state,
                                   now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), mindful: mindful,
                                   widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
        services.settings.saveToHealth = saveToHealth
        return services
    }

    func finishFocus(_ services: AppServices) {
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
    }

    @Test func aFinishedSessionIsWritten() {
        let services = makeServices()
        finishFocus(services)
        #expect(mindful.saved.count == 1)
        #expect(mindful.saved.first?.focusSeconds == Preset.classic.focus)
    }

    @Test func nothingIsWrittenUntilChosen() {
        let services = makeServices(saveToHealth: false)
        finishFocus(services)
        #expect(mindful.saved.isEmpty)
    }

    @Test func nothingIsWrittenWithoutAccess() {
        mindful.permission = .denied
        let services = makeServices()
        finishFocus(services)
        #expect(mindful.saved.isEmpty)
    }

    @Test func aSessionEndedEarlyWritesTheMinutesDone() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(14 * 60)
        services.engine.finishEarly()
        #expect(mindful.saved.first?.focusSeconds == TimeInterval(14 * 60))
    }

    @Test func keptOvertimeReplacesTheSample() throws {
        let services = makeServices()
        finishFocus(services)
        clock.advance(4 * 60)
        services.engine.keepOvertime()
        #expect(mindful.saved.count == 2)
        let last = try #require(mindful.saved.last)
        #expect(last.id == mindful.saved.first?.id)
        #expect(last.focusSeconds == Preset.classic.focus + 240)
    }

    @Test func deletingFromHistoryRemovesFromHealthAndUndoPutsItBack() throws {
        let services = makeServices()
        finishFocus(services)
        services.engine.skipBreak()
        let id = try #require(mindful.saved.first?.id)
        services.deleteSessions([id])
        #expect(mindful.removed == [id])
        services.undoDelete()
        #expect(mindful.saved.count == 2)
        #expect(mindful.saved.last?.id == id)
    }

    @Test func erasingHistoryRemovesClockinsSamples() {
        let services = makeServices()
        finishFocus(services)
        services.eraseHistory()
        #expect(mindful.removedAll == 1)
    }

    @Test func intentsWaitForHealthWrites() async {
        let services = makeServices()
        await services.settle()
        #expect(mindful.flushes == 1)
    }

    @Test func turningItOnAsksOnce() async {
        mindful.permission = .notDetermined
        let services = makeServices(saveToHealth: false)
        await services.setSaveToHealth(true)
        #expect(mindful.asked == 1)
        #expect(services.settings.saveToHealth)
        #expect(services.healthPermission == .authorized)
        await services.setSaveToHealth(false)
        await services.setSaveToHealth(true)
        #expect(mindful.asked == 1)
    }

    @Test func refusingTurnsItBackOff() async {
        mindful.permission = .notDetermined
        mindful.answer = .denied
        let services = makeServices(saveToHealth: false)
        await services.setSaveToHealth(true)
        #expect(!services.settings.saveToHealth)
        #expect(services.healthPermission == .denied)
    }

    @Test func olderSettingsDontWriteToHealth() throws {
        let old = Data(#"{"preset":"classic","longBreak":true}"#.utf8)
        #expect(try JSONDecoder().decode(TimerSettings.self, from: old).saveToHealth == false)
    }

    @Test func aWaitingWriteSurvivesARelaunchAndIsNeverDoubled() throws {
        // The test host has no Health access, so writes wait in the queue.
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let end = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var focus = CompletedFocus(id: UUID(), name: "Essay", startedAt: end.addingTimeInterval(-1800),
                                   completedAt: end, focusSeconds: 1500)
        MindfulMinutes(defaults: defaults).save(focus)
        focus.focusSeconds = 1740
        focus.completedAt = end.addingTimeInterval(240)
        MindfulMinutes(defaults: defaults).save(focus)

        let queue = MindfulMinutes(defaults: defaults).pending
        #expect(queue.count == 1)
        #expect(queue.first?.end == end.addingTimeInterval(240))
        #expect(queue.first?.start == end.addingTimeInterval(240 - 1740))
    }
}
