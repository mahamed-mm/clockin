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

    let symbols = InMemorySymbolBookStore()

    func makeServices() -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                    symbolStore: symbols, now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
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

    @Test func renamingRedrawsOutsideTheAppAndKeepsTheSymbol() throws {
        let services = makeServices()
        let focus = session("Chemsitry", minutesAgo: 30)
        let other = session("Spanish", minutesAgo: 90)
        try #require(services.history).restore([focus, other])
        services.setSymbol("flask.fill", for: "Chemsitry")
        services.setSymbol("globe", for: "Spanish")
        let reloads = widgets.reloads

        // A fresh name takes the pick along.
        services.renameSession(focus.id, to: "Chemistry")
        #expect(widgets.reloads == reloads + 1)
        #expect(services.symbol(for: "chemistry") == "flask.fill")
        #expect(symbols.book.picks["chemistry"] == "flask.fill")

        // A known name keeps its own.
        services.renameSession(focus.id, to: "spanish")
        #expect(services.symbol(for: "Spanish") == "globe")
    }

    @Test func aSymbolBelongsToTheNameAndRedrawsOutsideTheApp() {
        let services = makeServices()
        let reloads = widgets.reloads
        services.setSymbol("flask.fill", for: " Chemistry ")
        #expect(services.symbol(for: "CHEMISTRY") == "flask.fill")
        #expect(widgets.reloads == reloads + 1)

        // Nothing for an unnamed session, or a symbol that isn't offered.
        services.setSymbol("flask.fill", for: "  ")
        services.setSymbol("star.fill", for: "Chemistry")
        #expect(services.symbol(for: "") == SymbolCatalog.unnamed)
        #expect(services.symbol(for: "Chemistry") == "flask.fill")
        #expect(widgets.reloads == reloads + 1)
    }

    @Test func theLockScreenShowsTheNamesSymbolAndANewPick() {
        let services = makeServices()
        services.engine.start(name: "Chemistry")
        #expect(liveActivity.lastSymbol == "flask.fill")

        services.setSymbol("lightbulb.fill", for: "chemistry")
        #expect(liveActivity.lastSymbol == "lightbulb.fill")
    }

    @Test(arguments: [(nil, nil), (1_500.0, 25), (3_000, 50), (37 * 60, 35), (10, 5), (3 * 3_600, 60)] as [(TimeInterval?, Int?)])
    func aPastSessionsLengthOnTheDial(planned: TimeInterval?, minutes: Int?) {
        #expect(SessionLength(planned: planned)?.minutes == minutes)
    }

    @Test func startAgainSetsFocusUpWithoutStarting() {
        let services = makeServices()
        var typed = ""
        services.setLastSessionName = { typed = $0 }
        services.settings.length = .preset(.classic)

        #expect(services.prepareFocus(name: "Chemistry", planned: 50 * 60))
        #expect(typed == "Chemistry")
        #expect(services.settings.length == .preset(.deep))
        #expect(services.engine.active == nil)

        // No plan saved: the dial stays where it is.
        #expect(services.prepareFocus(name: "Spanish", planned: nil))
        #expect(services.settings.length == .preset(.deep))
    }

    @Test func startAgainWaitsWhileASessionRuns() {
        let services = makeServices()
        var typed = ""
        services.setLastSessionName = { typed = $0 }
        services.engine.start(name: "Running")
        #expect(!services.prepareFocus(name: "Chemistry", planned: 1_500))
        #expect(typed.isEmpty)
    }

    @Test func theWidgetGetsTodaysNamesSymbolsAndTheWeek() throws {
        let services = makeServices()
        try #require(services.history).restore([session("Chemistry", minutesAgo: 30)])
        services.setSymbol("lightbulb.fill", for: "Chemistry")
        let snapshot = try #require(widgets.lastSnapshot)
        #expect(snapshot.sessions.map(\.name) == ["Chemistry"])
        #expect(snapshot.sessions.map(\.symbol) == ["lightbulb.fill"])
        #expect(snapshot.week?.count == 7)
        #expect(snapshot.week?.reduce(0) { $0 + $1.sessions } == 1)
    }

    @Test func symbolsForNamesWithNoSessionAreForgotten() throws {
        let services = makeServices()
        services.lastSessionName = { "Typed but not started" }
        let focus = session("Chemistry", minutesAgo: 30)
        try #require(services.history).restore([focus, session("Spanish", minutesAgo: 90)])
        for name in ["Chemistry", "Spanish", "Typed but not started"] { services.setSymbol("globe", for: name) }
        services.engine.start(name: "Running now")
        services.setSymbol("pencil", for: "Running now")

        services.deleteSessions([focus.id])
        services.pruneSymbols()
        #expect(Set(services.symbolBook.picks.keys) == ["spanish", "typed but not started", "running now"])
    }

    @Test func eraseAllForgetsTheSymbolsToo() throws {
        let services = makeServices()
        try #require(services.history).restore([session("Chemistry", minutesAgo: 30)])
        services.setSymbol("flask.fill", for: "Chemistry")

        services.eraseHistory()
        #expect(services.symbolBook.picks.isEmpty)
        #expect(symbols.book.picks.isEmpty)
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

    @Test func recentNamesMatchIgnoringCaseAndSpaces() {
        let names = ["chemistry ", "Chemistry", "Spanish  vocab", "spanish vocab", "Essay"]
        #expect(HistoryService.recentNames(names, excluding: "", limit: 4) == ["chemistry ", "Spanish  vocab", "Essay"])
        #expect(HistoryService.recentNames(names, excluding: "CHEMISTRY", limit: 4) == ["Spanish  vocab", "Essay"])
    }

    @Test func recentNamesAreNewestFirstEachOnceAndNeverBlank() {
        let names = ["Essay", "", "Thesis", "Essay", "Spanish", "Reading", "Piano"]
        #expect(HistoryService.recentNames(names, excluding: "", limit: 4) == ["Essay", "Thesis", "Spanish", "Reading"])
        #expect(HistoryService.recentNames(names, excluding: " Thesis ", limit: 4) == ["Essay", "Spanish", "Reading", "Piano"])
    }
}
