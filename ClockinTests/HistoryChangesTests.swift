import Foundation
import SwiftData
import Testing
@testable import Clockin

/// Deleting, renaming and erasing saved sessions.
@MainActor
struct HistoryChangesTests {
    let clock = FakeClock()
    let widgets = SpyWidgets()
    let liveActivity = SpyLiveActivity()
    let announcer = SpyAnnouncer()

    func makeServices() -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                    now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                    liveActivity: liveActivity, notifications: SpyNotifier(), widgets: widgets,
                    haptics: SpyHaptics(), announce: { [announcer] in announcer.spoken.append($0) })
    }

    func session(_ name: String, minutesAgo: Double, outcome: FocusOutcome = .completed) -> CompletedFocus {
        let end = clock.now.addingTimeInterval(-minutesAgo * 60)
        return CompletedFocus(id: UUID(), name: name, startedAt: end.addingTimeInterval(-1_500), completedAt: end,
                              focusSeconds: 1_500, plannedSeconds: 1_500, outcome: outcome,
                              timeZoneIdentifier: "Europe/Oslo")
    }

    func saved(_ services: AppServices) throws -> [FocusRecord] {
        try services.container.mainContext.fetch(FetchDescriptor<FocusRecord>(
            sortBy: [SortDescriptor(\.completedAt)]))
    }

    @Test func deleteThenUndoPutsTheSameSessionBack() throws {
        let services = makeServices()
        let history = try #require(services.history)
        let original = session("Essay", minutesAgo: 30, outcome: .endedEarly)
        try history.restore([original, session("Other", minutesAgo: 90)])

        services.deleteSessions([original.id])
        #expect(try saved(services).map(\.name) == ["Other"])
        #expect(services.undoableDeletion.map(\.id) == [original.id])
        #expect(announcer.spoken.last?.contains("Undo") == true)

        services.undoDelete()
        let back = try #require(try saved(services).first { $0.id == original.id })
        #expect(back.completedFocus == original)
        #expect(services.undoableDeletion.isEmpty)
    }

    @Test func deletingRedrawsTodayOutsideTheApp() throws {
        let services = makeServices()
        let focus = session("Essay", minutesAgo: 30)
        try #require(services.history).restore([focus])
        services.engine.start(name: "Next")
        let syncs = liveActivity.calls.count

        services.deleteSessions([focus.id])
        #expect(widgets.lastSnapshot?.sessions.isEmpty == true)
        #expect(liveActivity.calls.count == syncs + 1)
        #expect(liveActivity.lastCompletedToday == 0)
    }

    @Test func renamingCleansTheName() throws {
        let services = makeServices()
        let focus = session("Essay", minutesAgo: 30)
        try #require(services.history).restore([focus])

        services.renameSession(focus.id, to: "  Thesis, chapter 2  ")
        #expect(try saved(services).first?.name == "Thesis, chapter 2")
    }

    @Test func eraseAllLeavesNothingToComeBack() throws {
        let services = makeServices()
        try #require(services.history).restore([session("A", minutesAgo: 30), session("B", minutesAgo: 90)])

        // One more finishes while the store is refusing saves, so it waits.
        let waiting = session("Waiting", minutesAgo: 5)
        let state = InMemorySessionStateStore()
        state.state = PersistedSessionState(pendingRecords: [waiting])
        let engineWithPending = AppServices(container: services.container, stateStore: state,
                                            now: { [clock] in clock.now }, calendar: osloCalendar,
                                            schedulesCompletion: false, liveActivity: SpyLiveActivity(),
                                            notifications: SpyNotifier(), widgets: SpyWidgets(), haptics: SpyHaptics(),
                                            announce: { _ in })
        #expect(engineWithPending.engine.pendingRecords.count == 1)

        engineWithPending.eraseHistory()
        engineWithPending.reconcile()
        #expect(try saved(engineWithPending).isEmpty)
        #expect(engineWithPending.engine.pendingRecords.isEmpty)
        #expect(state.state.pendingRecords == nil)
    }

    @Test func nothingChangesWhenTheStoreIsUnavailable() {
        let services = AppServices(container: AppServices.makeEmptyContainer(), historyUnavailable: true,
                                   stateStore: InMemorySessionStateStore(), schedulesCompletion: false,
                                   liveActivity: SpyLiveActivity(), notifications: SpyNotifier(),
                                   widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
        #expect(services.history == nil)
        services.deleteSessions([UUID()])
        #expect(services.undoableDeletion.isEmpty)
    }

    @Test func recentNamesAreNewestFirstEachOnceAndNeverBlank() {
        let names = ["Essay", "", "Thesis", "Essay", "Spanish", "Reading", "Piano"]
        #expect(HistoryService.recentNames(names, excluding: "", limit: 4) == ["Essay", "Thesis", "Spanish", "Reading"])
        #expect(HistoryService.recentNames(names, excluding: " Thesis ", limit: 4) == ["Essay", "Spanish", "Reading", "Piano"])
    }
}
