import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// History as files: CSV for spreadsheets, and a JSON backup that can be
/// restored. With everything on this iPhone and no iCloud, the backup is
/// how History survives a lost or replaced phone.
enum HistoryExport {
    /// Bumped for changes older builds couldn't read. Format 2 added each
    /// name's symbol, format 3 parked thoughts; older backups still restore,
    /// without them.
    static let backupFormat = 3

    /// One session in a backup.
    struct Session: Codable, Equatable {
        var id: UUID
        var name: String
        var startedAt: Date
        var completedAt: Date
        var focusSeconds: Double
        var plannedSeconds: Double?
        var outcome: String?
        var timeZone: String?
    }

    struct Backup: Codable {
        var format: Int
        var exportedAt: Date
        var sessions: [Session]
        /// The symbol picked for each name, by name. Nil before format 2.
        var symbols: [String: String]?
        /// Parked thoughts kept with each session, by session id. Nil before format 3.
        var thoughts: [String: [ParkedThought]]?
        /// Thoughts from cancelled sessions. Nil before format 3.
        var unfiledThoughts: [ParkedThought]?
    }

    enum ImportError: LocalizedError {
        case unreadable
        case newerFormat

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "This file isn't a Clockin backup.")
            case .newerFormat: String(localized: "This backup is from a newer version of Clockin.")
            }
        }
    }

    // MARK: Dates

    /// Down to the millisecond, so a backup restores without a single change.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func dateString(_ date: Date) -> String { date.formatted(dateStyle) }

    private static func parseDate(_ string: String) -> Date? {
        (try? dateStyle.parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string))
    }

    // MARK: JSON backup

    static func backup(_ sessions: [CompletedFocus], symbols: SymbolBook = SymbolBook(),
                       thoughts: ThoughtBook = ThoughtBook(), exportedAt: Date) throws -> Data {
        let ids = Set(sessions.map(\.id))
        let kept = thoughts.bySession.filter { ids.contains($0.key) && !$0.value.isEmpty }
        let backup = Backup(format: backupFormat, exportedAt: exportedAt, sessions: sessions.map {
            Session(id: $0.id, name: $0.name, startedAt: $0.startedAt, completedAt: $0.completedAt,
                    focusSeconds: $0.focusSeconds, plannedSeconds: $0.plannedSeconds, outcome: $0.outcome?.rawValue,
                    timeZone: $0.timeZoneIdentifier)
        }, symbols: symbols.picks,
        thoughts: Dictionary(uniqueKeysWithValues: kept.map { ($0.key.uuidString, $0.value) }),
        unfiledThoughts: thoughts.unfiled)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateString(date))
        }
        return try encoder.encode(backup)
    }

    static func readBackup(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date")
            }
            return date
        }
        // Read the format first, so a newer backup says so instead of failing to parse.
        struct Header: Decodable { var format: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw ImportError.unreadable }
        guard header.format <= backupFormat else { throw ImportError.newerFormat }
        do {
            return try decoder.decode(Backup.self, from: data)
        } catch {
            throw ImportError.unreadable
        }
    }

    // MARK: Import plan

    /// What a restore would do, worked out before anything is saved.
    struct ImportPlan: Equatable {
        var new: [CompletedFocus] = []
        var updated: [CompletedFocus] = []
        var unchanged = 0
        /// Sessions that didn't make sense (or repeated an id) and are skipped.
        var skipped = 0
        /// Symbol picks from the backup for names without one on this phone.
        var symbols: [String: String] = [:]
        /// The backup's parked thoughts, merged by id with the ones here.
        var thoughts = ThoughtBook()

        var changes: [CompletedFocus] { new + updated }
        var isEmpty: Bool { changes.isEmpty }
    }

    /// Checks every session and compares it with what's saved, by id.
    static func plan(_ backup: Backup, existing: [UUID: CompletedFocus], symbols: SymbolBook = SymbolBook(),
                     now: Date) -> ImportPlan {
        var plan = ImportPlan()
        var merged = symbols
        merged.merge(backup.symbols ?? [:])
        plan.symbols = merged.picks.filter { symbols.picks[$0.key] == nil }
        plan.thoughts = thoughts(in: backup)
        var seen = Set<UUID>()
        for session in backup.sessions {
            guard seen.insert(session.id).inserted, let focus = validated(session, now: now) else {
                plan.skipped += 1
                continue
            }
            if let saved = existing[focus.id] {
                if isSame(saved, focus) { plan.unchanged += 1 } else { plan.updated.append(focus) }
            } else {
                plan.new.append(focus)
            }
        }
        return plan
    }

    /// A backup's thoughts, cleaned like typed ones; anything unreadable is left out.
    private static func thoughts(in backup: Backup) -> ThoughtBook {
        func cleaned(_ thoughts: [ParkedThought]) -> [ParkedThought] {
            thoughts.compactMap { thought in
                ParkedThought.clean(thought.text).map {
                    ParkedThought(id: thought.id, text: $0, parkedAt: thought.parkedAt, done: thought.done)
                }
            }
        }
        var book = ThoughtBook()
        for (key, thoughts) in backup.thoughts ?? [:] {
            guard let id = UUID(uuidString: key), backup.sessions.contains(where: { $0.id == id }) else { continue }
            book.file(cleaned(thoughts), under: id)
        }
        book.unfile(cleaned(backup.unfiledThoughts ?? []))
        return book
    }

    /// The longest one session can plausibly be.
    private static let longestSession: TimeInterval = 24 * 3_600

    private static func validated(_ session: Session, now: Date) -> CompletedFocus? {
        let span = session.completedAt.timeIntervalSince(session.startedAt)
        guard span > 0, session.completedAt <= now.addingTimeInterval(60),
              session.focusSeconds > 0, session.focusSeconds <= min(span + 1, longestSession) else { return nil }
        if let planned = session.plannedSeconds, !(planned > 0 && planned <= longestSession) { return nil }
        return CompletedFocus(id: session.id, name: ActiveSession.cleanName(session.name),
                              startedAt: session.startedAt, completedAt: session.completedAt,
                              focusSeconds: session.focusSeconds, plannedSeconds: session.plannedSeconds,
                              outcome: session.outcome.flatMap(FocusOutcome.init(rawValue:)),
                              timeZoneIdentifier: session.timeZone.flatMap { TimeZone(identifier: $0)?.identifier })
    }

    private static func isSame(_ a: CompletedFocus, _ b: CompletedFocus) -> Bool {
        func close(_ x: Date, _ y: Date) -> Bool { abs(x.timeIntervalSince(y)) < 0.001 }
        return a.name == b.name && close(a.startedAt, b.startedAt) && close(a.completedAt, b.completedAt)
            && a.focusSeconds == b.focusSeconds && a.plannedSeconds == b.plannedSeconds
            && (a.outcome ?? .completed) == (b.outcome ?? .completed)
    }

    // MARK: CSV

    /// New columns go at the end, so sheets that read by position keep working.
    static let csvHeader = "id,name,started_at,completed_at,focus_seconds,planned_seconds,outcome,time_zone,symbol"

    /// One row per session, oldest first, for Numbers or Excel. Export only.
    static func csv(_ sessions: [CompletedFocus], symbols: SymbolBook = SymbolBook()) -> String {
        let rows = sessions.map { focus in
            [focus.id.uuidString, csvField(focus.name), dateString(focus.startedAt), dateString(focus.completedAt),
             number(focus.focusSeconds), focus.plannedSeconds.map(number) ?? "",
             (focus.outcome ?? .completed).rawValue, focus.timeZoneIdentifier ?? "",
             SymbolBook.key(for: focus.name).isEmpty ? "" : symbols.symbol(for: focus.name)].joined(separator: ",")
        }
        return ([csvHeader] + rows).joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field when it holds a comma, quote or line break. A field
    /// that a spreadsheet would run as a formula gets a leading apostrophe.
    static func csvField(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
    }

    /// "Clockin 2026-10-12"
    static func fileName(_ kind: String, on date: Date) -> String {
        "Clockin \(kind) \(date.formatted(.iso8601.year().month().day()))"
    }
}

/// A finished export, handed to the system's file picker.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .json]

    let data: Data
    let contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
