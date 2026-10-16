import Foundation
import SwiftData
import Testing
@testable import Clockin

/// Rename everywhere: every session with a name, what's running, the plan
/// and the field, with Undo, and two subjects becoming one.
@MainActor
struct SubjectRenameTests {
    let clock = FakeClock()
    let live = SpyLiveActivity()
    let symbols = InMemorySymbolBookStore()
    let plans = InMemorySetPlanStore()

    final class Field {
        var name = ""
    }
    let field = Field()

    func makeServices() -> AppServices {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   symbolStore: symbols, planStore: plans, now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false, liveActivity: live,
                                   notifications: SpyNotifier(), widgets: SpyWidgets(), haptics: SpyHaptics(),
                                   announce: { _ in })
        services.lastSessionName = { [field] in field.name }
        services.setLastSessionName = { [field] in field.name = $0 }
        return services
    }

    func session(_ name: String, minutesAgo: Double) -> CompletedFocus {
        let end = clock.now.addingTimeInterval(-minutesAgo * 60)
        return CompletedFocus(id: UUID(), name: name, startedAt: end.addingTimeInterval(-1_500), completedAt: end,
                              focusSeconds: 1_500, plannedSeconds: 1_500, outcome: .completed,
                              timeZoneIdentifier: "Europe/Oslo")
    }

    func names(_ services: AppServices) throws -> [String] {
        try services.container.mainContext.fetch(FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.completedAt)]))
            .map(\.name)
    }

    @Test func everySpellingTakesTheNewNameAtOnce() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90), session("Chem ", minutesAgo: 60),
                                                session("Essay", minutesAgo: 30)])
        services.setSymbol("flask.fill", for: "chem")
        #expect(services.renameSubject(key: "chem", to: "  Chemistry "))
        #expect(try names(services) == ["Chemistry", "Chemistry", "Essay"])
        #expect(services.symbol(for: "Chemistry") == "flask.fill")
        guard case .rename(let rename)? = services.historyUndo else { Issue.record("No undo"); return }
        #expect(rename.name == "Chemistry")
    }

    @Test func undoPutsEveryNameAndSymbolBack() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90), session("Chem ", minutesAgo: 60)])
        services.renameSubject(key: "chem", to: "Chemistry")
        services.setSymbol("flask.fill", for: "Chemistry")
        services.undoHistoryChange()
        #expect(try names(services) == ["chem", "Chem "])
        #expect(services.symbolBook.picks["chemistry"] == nil)
        #expect(services.historyUndo == nil)
    }

    @Test func afterTheWindowTheRenameStands() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90)])
        services.renameSubject(key: "chem", to: "Chemistry")
        services.expireHistoryUndo()
        services.undoHistoryChange()
        #expect(try names(services) == ["Chemistry"])
    }

    @Test func aNewSpellingOfTheSameNameIsNoMerge() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chemistry", minutesAgo: 90)])
        #expect(!services.mergesInto("Chemistry", from: "chemistry"))
        #expect(services.renameSubject(key: "chemistry", to: "Chemistry"))
        #expect(try names(services) == ["Chemistry"])
    }

    @Test func intoAnotherSubjectTheTwoBecomeOneAndItsSymbolStays() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90), session("Chemistry", minutesAgo: 60)])
        services.setSymbol("flask.fill", for: "Chemistry")
        services.setSymbol("lightbulb.fill", for: "chem")
        #expect(services.mergesInto("Chemistry", from: "chem"))
        services.renameSubject(key: "chem", to: "Chemistry")
        #expect(try names(services) == ["Chemistry", "Chemistry"])
        #expect(services.symbol(for: "Chemistry") == "flask.fill")
        services.undoHistoryChange()
        #expect(try names(services) == ["chem", "Chemistry"])
        #expect(services.symbol(for: "chem") == "lightbulb.fill")
    }

    @Test func aBlankNameIsRefused() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90)])
        #expect(!services.renameSubject(key: "chem", to: "   "))
        #expect(try names(services) == ["chem"])
    }

    @Test func theRunningSessionKeepsItsTimeAndTakesTheName() throws {
        let services = makeServices()
        services.engine.start(name: "chem")
        clock.advance(5 * 60)
        let before = try #require(services.engine.active)
        let events = live.calls.count
        services.renameSubject(key: "chem", to: "Chemistry")
        var after = try #require(services.engine.active)
        #expect(after.name == "Chemistry")
        after.name = before.name
        #expect(after == before, "Only the name changes")
        #expect(live.calls.count == events + 1, "One quiet resync, not a new session")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(try names(services) == ["Chemistry"])
    }

    @Test func aCancelledSessionComesBackWithTheNewName() throws {
        let services = makeServices()
        services.engine.start(name: "chem")
        services.engine.cancel()
        services.renameSubject(key: "chem", to: "Chemistry")
        #expect(services.engine.undoable != nil, "The cancel's Undo is still there")
        services.engine.undo()
        #expect(services.engine.active?.name == "Chemistry")
    }

    @Test func thePlanAndTheFieldFollowAndComeBack() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90)])
        var plan = SetPlan(day: services.today)
        plan.add("chem")
        plan.add("Essay")
        services.editSet(plan)
        field.name = "chem"
        services.renameSubject(key: "chem", to: "Chemistry")
        #expect(services.todaysSet?.slots.map(\.name) == ["Chemistry", "Essay"])
        #expect(field.name == "Chemistry")
        services.undoHistoryChange()
        #expect(services.todaysSet?.slots.map(\.name) == ["chem", "Essay"])
        #expect(field.name == "chem")
    }

    @Test func aDeleteThenARenameKeepsOnlyTheRenamesUndo() throws {
        let services = makeServices()
        let gone = session("Essay", minutesAgo: 30)
        try #require(services.history).restore([gone, session("chem", minutesAgo: 90)])
        services.deleteSessions([gone.id])
        services.renameSubject(key: "chem", to: "Chemistry")
        services.undoHistoryChange()
        #expect(try names(services) == ["chem"], "The delete stands; the rename was undone")
    }

    @Test func aBackupAfterARenameHasTheNewNames() throws {
        let services = makeServices()
        try #require(services.history).restore([session("chem", minutesAgo: 90)])
        services.renameSubject(key: "chem", to: "Chemistry")
        let data = try HistoryExport.backup(try #require(services.history).allSessions(), exportedAt: clock.now)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("Chemistry") && !text.contains("\"chem\""))
    }
}

/// A rename keeps the symbol a subject showed.
@MainActor
struct SubjectRenameSymbolTests {
    @Test func aSuggestedSymbolStaysWithTheNewName() throws {
        let clock = FakeClock()
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   now: { clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), widgets: SpyWidgets(),
                                   haptics: SpyHaptics(), announce: { _ in })
        let end = clock.now.addingTimeInterval(-600)
        try #require(services.history).restore([CompletedFocus(id: UUID(), name: "Piano practice",
                                                                startedAt: end.addingTimeInterval(-1_500),
                                                                completedAt: end, focusSeconds: 1_500)])
        let before = services.symbol(for: "Piano practice")
        #expect(before == "music.note")
        services.renameSubject(key: "piano practice", to: "Lessons")
        #expect(services.symbol(for: "Lessons") == before)
        services.undoHistoryChange()
        #expect(services.symbolBook.picks.isEmpty)
    }
}
