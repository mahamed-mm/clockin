import Foundation
import SwiftData
import Testing
@testable import Clockin

/// CSV for spreadsheets, and a JSON backup that restores without loss.
@MainActor
struct HistoryExportTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000.123)

    func session(_ name: String, endedAgo: TimeInterval, seconds: Double = 1_500,
                 outcome: FocusOutcome? = .completed) -> CompletedFocus {
        let end = now.addingTimeInterval(-endedAgo)
        return CompletedFocus(id: UUID(), name: name, startedAt: end.addingTimeInterval(-seconds - 0.456),
                              completedAt: end, focusSeconds: seconds, plannedSeconds: 1_500, outcome: outcome,
                              timeZoneIdentifier: "Europe/Oslo")
    }

    func makeServices(historyUnavailable: Bool = false) -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), historyUnavailable: historyUnavailable,
                    stateStore: InMemorySessionStateStore(), now: { [now] in now }, calendar: osloCalendar,
                    schedulesCompletion: false, liveActivity: SpyLiveActivity(), notifications: SpyNotifier(),
                    widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
    }

    // MARK: CSV

    @Test func csvQuotesWhatWouldBreakAColumn() {
        #expect(HistoryExport.csvField("Essay") == "Essay")
        #expect(HistoryExport.csvField("Read, then write") == "\"Read, then write\"")
        #expect(HistoryExport.csvField("The \"big\" one") == "\"The \"\"big\"\" one\"")
        #expect(HistoryExport.csvField("Two\nlines") == "\"Two\nlines\"")
    }

    @Test func csvNeverHandsASpreadsheetAFormula() {
        #expect(HistoryExport.csvField("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(HistoryExport.csvField("+1 chapter") == "'+1 chapter")
        #expect(HistoryExport.csvField("@home") == "'@home")
    }

    @Test func csvHasAHeaderAndARowPerSession() {
        let early = session("Essay, part 1", endedAgo: 600, seconds: 300, outcome: .endedEarly)
        let lines = HistoryExport.csv([early]).components(separatedBy: "\r\n")
        #expect(lines[0] == HistoryExport.csvHeader)
        #expect(lines[1].hasPrefix("\(early.id.uuidString),\"Essay, part 1\","))
        #expect(lines[1].hasSuffix(",300,1500,endedEarly,Europe/Oslo,book.closed.fill"))
        #expect(lines.count == 3) // Header, row, and the final line break.
    }

    @Test func csvAddsEachNamesSymbolLast() {
        var book = SymbolBook()
        book.pick("flask.fill", for: "Chemistry")
        let rows = HistoryExport.csv([session("chemistry", endedAgo: 600), session("", endedAgo: 900)], symbols: book)
            .components(separatedBy: "\r\n")
        #expect(HistoryExport.csvHeader.hasPrefix("id,name,started_at,completed_at,focus_seconds,planned_seconds,outcome,time_zone,"))
        #expect(HistoryExport.csvHeader.hasSuffix(",symbol"))
        #expect(rows[1].hasSuffix(",Europe/Oslo,flask.fill"))
        #expect(rows[2].hasSuffix(",Europe/Oslo,")) // Unnamed: no symbol.
    }

    // MARK: Backup

    @Test func aBackupRestoresWithoutASingleChange() throws {
        let sessions = [session("Essay", endedAgo: 600), session("", endedAgo: 7_200, outcome: nil)]
        let backup = try HistoryExport.readBackup(try HistoryExport.backup(sessions, exportedAt: now))
        #expect(backup.format == 2)

        let existing = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let plan = HistoryExport.plan(backup, existing: existing, now: now)
        #expect(plan.unchanged == 2)
        #expect(plan.isEmpty)
    }

    @Test func aRestoreSortsSessionsIntoNewUpdatedAndSkipped() throws {
        let kept = session("Essay", endedAgo: 600)
        var renamed = session("Old name", endedAgo: 1_200)
        let fresh = session("Spanish", endedAgo: 3_600)
        let existing = [kept.id: kept, renamed.id: renamed]
        renamed.name = "New name"

        var backup = try HistoryExport.readBackup(try HistoryExport.backup([kept, renamed, fresh], exportedAt: now))
        backup.sessions.append(backup.sessions[2]) // A repeated id.
        var future = backup.sessions[0]
        future.id = UUID()
        future.completedAt = now.addingTimeInterval(3_600)
        future.startedAt = future.completedAt.addingTimeInterval(-1_500)
        var tooLong = backup.sessions[0]
        tooLong.id = UUID()
        tooLong.focusSeconds = 99_999
        backup.sessions += [future, tooLong]

        let plan = HistoryExport.plan(backup, existing: existing, now: now)
        #expect(plan.unchanged == 1)
        #expect(plan.updated.map(\.name) == ["New name"])
        #expect(plan.new.map(\.id) == [fresh.id])
        #expect(plan.skipped == 3)
    }

    @Test func aBackupFromANewerBuildSaysSo() {
        let json = #"{"format":3,"exportedAt":"2027-01-15T08:00:00.000Z","sessions":[]}"#
        #expect(throws: HistoryExport.ImportError.newerFormat) { try HistoryExport.readBackup(Data(json.utf8)) }
        #expect(throws: HistoryExport.ImportError.unreadable) { try HistoryExport.readBackup(Data("hello".utf8)) }
    }

    @Test func aFormatOneBackupStillRestores() throws {
        let json = #"""
        {"format":1,"exportedAt":"2027-01-15T08:00:00.000Z","sessions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
        "name":"Essay","startedAt":"2027-01-15T07:00:00.000Z","completedAt":"2027-01-15T07:25:00.000Z",
        "focusSeconds":1500}]}
        """#
        let backup = try HistoryExport.readBackup(Data(json.utf8))
        #expect(backup.symbols == nil)
        let plan = HistoryExport.plan(backup, existing: [:], now: .distantFuture)
        #expect(plan.new.map(\.name) == ["Essay"])
        #expect(plan.symbols.isEmpty)
    }

    @Test func aRestoreBringsSymbolsButKeepsThisPhonesPicks() throws {
        var exported = SymbolBook()
        exported.pick("flask.fill", for: "Chemistry")
        exported.pick("globe", for: "Spanish")
        let file = try HistoryExport.backup([session("Chemistry", endedAgo: 600)], symbols: exported, exportedAt: now)
        var here = SymbolBook()
        here.pick("pencil", for: "chemistry")

        let plan = HistoryExport.plan(try HistoryExport.readBackup(file), existing: [:], symbols: here, now: now)
        #expect(plan.symbols == ["spanish": "globe"])
    }

    @Test func exportEraseRestoreGivesHistoryBack() throws {
        let services = makeServices()
        let history = try #require(services.history)
        let sessions = [session("Essay", endedAgo: 600), session("Spanish", endedAgo: 90_000, seconds: 900)]
        try history.restore(sessions)
        services.setSymbol("pencil", for: "Essay")
        let file = try HistoryExport.backup(try history.allSessions(), symbols: services.symbolBook, exportedAt: now)

        services.eraseHistory()
        #expect(try history.allSessions().isEmpty)
        #expect(services.symbol(for: "Essay") == SymbolCatalog.unnamed)

        let plan = try services.planImport(of: file)
        #expect(plan.new.count == 2)
        try services.importSessions(plan)
        let restored = try history.allSessions()
        let original = sessions.sorted { $0.completedAt < $1.completedAt }
        #expect(restored.map(\.id) == original.map(\.id))
        #expect(restored.map(\.name) == original.map(\.name))
        #expect(restored.map(\.focusSeconds) == original.map(\.focusSeconds))
        #expect(restored.map(\.timeZoneIdentifier) == original.map(\.timeZoneIdentifier))
        #expect(services.symbol(for: "Essay") == "pencil")

        // Restoring the same file again changes nothing.
        let again = try services.planImport(of: file)
        #expect(again.unchanged == 2)
        #expect(again.isEmpty)
    }

    @Test func noRestoreWhileTheStoreIsUnavailable() throws {
        let services = makeServices(historyUnavailable: true)
        let file = try HistoryExport.backup([session("Essay", endedAgo: 600)], exportedAt: now)
        #expect(throws: HistoryExport.ImportError.self) { try services.planImport(of: file) }
    }
}
