import Foundation
import Testing
@testable import Clockin

/// Parked thoughts: kept with their session, never lost, and never shown
/// anywhere outside the app.
@MainActor
struct ThoughtStoreTests {
    let clock = FakeClock()
    let thoughtStore = InMemoryThoughtStore()
    let state = InMemorySessionStateStore()

    func makeServices() -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), stateStore: state, thoughtStore: thoughtStore,
                    now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                    liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), alarm: SpyAlarm(),
                    widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
    }

    @Test func aThoughtIsOneTidyLine() {
        #expect(ParkedThought.clean("  Call the dentist \n") == "Call the dentist")
        #expect(ParkedThought.clean("Two\nlines") == "Two lines")
        #expect(ParkedThought.clean("   \n ") == nil)
        #expect(ParkedThought.clean(String(repeating: "a", count: 500))?.count == ParkedThought.maxLength)
    }

    @Test func thoughtsParkOnlyDuringFocus() {
        let services = makeServices()
        #expect(!services.park("Nothing running"))
        services.engine.start(name: "Essay")
        #expect(services.park("Buy milk"))
        #expect(!services.park("  "))
        #expect(services.engine.active?.thoughts?.map(\.text) == ["Buy milk"])
        // Saved with the running session, so a relaunch keeps it.
        #expect(state.load().active?.thoughts?.map(\.text) == ["Buy milk"])
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        #expect(!services.park("On a break"))
    }

    @Test func aFinishedSessionKeepsItsThoughts() throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        let id = try #require(services.engine.active?.id)
        services.park("Buy milk")
        services.park("Email Sam")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(services.thoughts.thoughts(for: id).map(\.text) == ["Buy milk", "Email Sam"])
        #expect(services.thoughtsAfterFocus?.thoughts.count == 2)
        #expect(thoughtStore.load().thoughts(for: id).count == 2)

        // Through the break, the list is still the focus session's.
        services.engine.startBreak()
        #expect(services.thoughtsAfterFocus?.session == id)
        #expect(services.thoughtsAfterFocus?.thoughts.count == 2)

        let first = try #require(services.thoughts.thoughts(for: id).first)
        services.setThoughtDone(true, first.id)
        #expect(services.thoughts.thoughts(for: id).first?.done == true)
    }

    @Test func finishingEarlyKeepsThemToo() throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        let id = try #require(services.engine.active?.id)
        services.park("Buy milk")
        clock.advance(10 * 60)
        services.engine.finishEarly()
        #expect(services.thoughts.thoughts(for: id).map(\.text) == ["Buy milk"])
    }

    @Test func aCancelledSessionsThoughtsAreKeptUnfiledAndUndoTakesThemBack() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.park("Buy milk")
        services.engine.cancel()
        #expect(services.thoughts.unfiled.map(\.text) == ["Buy milk"])

        services.engine.undoCancel()
        #expect(services.thoughts.unfiled.isEmpty)
        #expect(services.engine.active?.thoughts?.count == 1)

        services.engine.cancel()
        #expect(services.thoughts.unfiled.count == 1)
        services.clearUnfiledThoughts()
        #expect(services.thoughts.unfiled.isEmpty)
    }

    @Test func deletingASessionForgetsItsThoughtsOnceUndoIsGone() throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        let id = try #require(services.engine.active?.id)
        services.park("Buy milk")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.skipBreak()

        services.deleteSessions([id])
        services.pruneThoughts()
        #expect(services.thoughts.thoughts(for: id).count == 1, "kept while Undo is offered")
        services.undoDelete()
        services.pruneThoughts()
        #expect(services.thoughts.thoughts(for: id).count == 1)

        services.deleteSessions([id])
        services.expireDeletion()
        services.pruneThoughts()
        #expect(services.thoughts.thoughts(for: id).isEmpty)
    }

    @Test func eraseAllClearsEveryThought() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.park("Buy milk")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        services.engine.skipBreak()
        services.engine.start(name: "Again")
        services.park("Call Sam")
        services.engine.cancel()
        services.eraseHistory()
        #expect(services.thoughts == ThoughtBook())
        #expect(thoughtStore.load() == ThoughtBook())
    }

    @Test func noThoughtLeavesTheApp() throws {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.park("A very private thought")
        let session = try #require(services.engine.active)
        let content = FocusActivityAttributes.ContentState(session: session, completedToday: 1)
        let card = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        #expect(!card.contains("private thought"))
        clock.advance(Preset.classic.focus)
        services.reconcile()
        let snapshot = String(decoding: try JSONEncoder().encode(services.widgetSnapshot()), as: UTF8.self)
        #expect(!snapshot.contains("private thought"))
    }

    @Test func olderStateLoadsWithoutThoughts() throws {
        let json = #"{"active":{"id":"6F1A7E6C-0B8C-4C6A-9E57-1E2D3C4B5A69","name":"Essay","phase":"focus","plannedDuration":1500,"focusStartedAt":0,"state":{"running":{"endDate":1500}}},"format":4}"#
        let state = try JSONDecoder().decode(PersistedSessionState.self, from: Data(json.utf8))
        #expect(state.active?.thoughts == nil)
        #expect(state.active?.focusSound == nil)
        #expect(PersistedSessionState.currentFormat == 5)
    }

    @Test func aBadFileStartsAfresh() throws {
        let url = URL.temporaryDirectory.appending(path: "thoughts-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("unreadable"))
        }
        let store = FileThoughtStore(url: url)
        #expect(store.load() == ThoughtBook())
        var book = ThoughtBook()
        book.unfile([ParkedThought(id: UUID(), text: "Kept", parkedAt: clock.now)])
        store.save(book)
        #expect(store.load() == book)
    }
}

/// Backups carry parked thoughts from format 3; older ones restore without.
@MainActor
struct ThoughtBackupTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func focus(_ name: String) -> CompletedFocus {
        CompletedFocus(id: UUID(), name: name, startedAt: now - 1600, completedAt: now - 100, focusSeconds: 1500,
                       plannedSeconds: 1500, outcome: .completed)
    }

    @Test func thoughtsRoundTrip() throws {
        let essay = focus("Essay")
        var book = ThoughtBook()
        book.file([ParkedThought(id: UUID(), text: "Buy milk", parkedAt: now - 500, done: true)], under: essay.id)
        book.unfile([ParkedThought(id: UUID(), text: "Call Sam", parkedAt: now - 900)])
        let data = try HistoryExport.backup([essay], thoughts: book, exportedAt: now)
        let backup = try HistoryExport.readBackup(data)
        #expect(backup.format == 3)
        let plan = HistoryExport.plan(backup, existing: [:], now: now)
        #expect(plan.thoughts.thoughts(for: essay.id).map(\.text) == ["Buy milk"])
        #expect(plan.thoughts.thoughts(for: essay.id).first?.done == true)
        #expect(plan.thoughts.unfiled.map(\.text) == ["Call Sam"])
    }

    @Test func thoughtsOfSessionsNotInTheBackupAreLeftOut() throws {
        let essay = focus("Essay")
        var book = ThoughtBook()
        book.file([ParkedThought(id: UUID(), text: "Gone", parkedAt: now)], under: UUID())
        book.file([ParkedThought(id: UUID(), text: "Kept", parkedAt: now)], under: essay.id)
        let plan = HistoryExport.plan(try HistoryExport.readBackup(
            try HistoryExport.backup([essay], thoughts: book, exportedAt: now)), existing: [:], now: now)
        #expect(plan.thoughts.bySession.count == 1)
    }

    @Test func aFormatTwoBackupRestoresWithoutThoughts() throws {
        let json = """
            {"format":2,"exportedAt":"2027-01-15T08:00:00.000Z","sessions":[],"symbols":{"essay":"pencil"}}
            """
        let backup = try HistoryExport.readBackup(Data(json.utf8))
        #expect(backup.thoughts == nil)
        #expect(HistoryExport.plan(backup, existing: [:], now: now).thoughts == ThoughtBook())
    }

    @Test func mergingNeverReplacesAThoughtKeptHere() {
        let id = UUID()
        let thought = ParkedThought(id: UUID(), text: "Buy milk", parkedAt: now, done: true)
        var here = ThoughtBook()
        here.file([thought], under: id)
        var incoming = ThoughtBook()
        var older = thought
        older.done = nil
        incoming.file([older, ParkedThought(id: UUID(), text: "New", parkedAt: now)], under: id)
        incoming.unfile([thought])
        here.merge(incoming)
        #expect(here.thoughts(for: id).map(\.text) == ["Buy milk", "New"])
        #expect(here.thoughts(for: id).first?.done == true)
        #expect(here.unfiled.isEmpty)
    }

    @Test func theCSVStaysAsItWas() {
        #expect(HistoryExport.csv([focus("Essay")]).hasPrefix(
            "id,name,started_at,completed_at,focus_seconds,planned_seconds,outcome,time_zone,symbol"))
    }
}
