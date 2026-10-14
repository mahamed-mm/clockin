import Foundation
import SwiftData

/// Changes to saved sessions: delete, rename, erase, and putting deleted
/// sessions back. Every change is one save, rolled back if it fails, so the
/// store never keeps half of one.
@MainActor
final class HistoryService {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Deletes the sessions with these ids and returns them as they were,
    /// so they can be put back.
    @discardableResult
    func delete(ids: Set<UUID>) throws -> [CompletedFocus] {
        let records = try context.fetch(FetchDescriptor<FocusRecord>(predicate: #Predicate { ids.contains($0.id) }))
        let removed = records.map(\.completedFocus)
        records.forEach(context.delete)
        try save()
        return removed
    }

    /// Renames a session and returns its old name, or nil if it's gone.
    @discardableResult
    func rename(id: UUID, to name: String) throws -> String? {
        var descriptor = FetchDescriptor<FocusRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return nil }
        let old = record.name
        record.name = ActiveSession.cleanName(name)
        try save()
        return old
    }

    /// Every name a saved session has, once each.
    func distinctNames() throws -> Set<String> {
        var descriptor = FetchDescriptor<FocusRecord>()
        descriptor.propertiesToFetch = [\.name]
        return Set(try context.fetch(descriptor).map(\.name))
    }

    /// Deletes every saved session. Returns how many there were.
    @discardableResult
    func deleteAll() throws -> Int {
        let count = try context.fetchCount(FetchDescriptor<FocusRecord>())
        try context.delete(model: FocusRecord.self)
        try save()
        return count
    }

    /// Puts sessions back exactly as they were. Any already there are left alone.
    func restore(_ sessions: [CompletedFocus]) throws {
        let ids = Set(sessions.map(\.id))
        let present = Set(try context.fetch(FetchDescriptor<FocusRecord>(predicate: #Predicate { ids.contains($0.id) }))
            .map(\.id))
        for focus in sessions where !present.contains(focus.id) {
            context.insert(FocusRecord(focus))
        }
        try save()
    }

    /// Every saved session, oldest first, for export.
    func allSessions() throws -> [CompletedFocus] {
        try context.fetch(FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.completedAt)])).map(\.completedFocus)
    }

    /// The saved sessions with these ids, by id.
    func sessions(ids: Set<UUID>) throws -> [UUID: CompletedFocus] {
        let records = try context.fetch(FetchDescriptor<FocusRecord>(predicate: #Predicate { ids.contains($0.id) }))
        return Dictionary(records.map { ($0.id, $0.completedFocus) }, uniquingKeysWith: { first, _ in first })
    }

    /// Saves each session over the one with its id, or as a new one.
    func upsert(_ sessions: [CompletedFocus]) throws {
        let ids = Set(sessions.map(\.id))
        let records = try context.fetch(FetchDescriptor<FocusRecord>(predicate: #Predicate { ids.contains($0.id) }))
        let existing = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for focus in sessions {
            if let record = existing[focus.id] {
                record.name = focus.name
                record.startedAt = focus.startedAt
                record.completedAt = focus.completedAt
                record.focusSeconds = focus.focusSeconds
                record.plannedSeconds = focus.plannedSeconds
                record.outcomeRaw = (focus.outcome ?? .completed).rawValue
                record.timeZoneIdentifier = focus.timeZoneIdentifier ?? record.timeZoneIdentifier
            } else {
                context.insert(FocusRecord(focus))
            }
        }
        try save()
    }

    /// Recent session names for quick picks: newest first, each once (as
    /// last spelled), no blanks, leaving out what's already typed. Names
    /// match the way their symbols do, ignoring case and extra spaces.
    nonisolated static func recentNames(_ names: [String], excluding typed: String, limit: Int) -> [String] {
        var seen: Set<String> = [SymbolBook.key(for: typed)]
        var picks: [String] = []
        for name in names {
            let key = SymbolBook.key(for: name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            picks.append(name)
            if picks.count == limit { break }
        }
        return picks
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension FocusRecord {
    convenience init(_ focus: CompletedFocus) {
        self.init(id: focus.id, name: focus.name, startedAt: focus.startedAt, completedAt: focus.completedAt,
                  focusSeconds: focus.focusSeconds, plannedSeconds: focus.plannedSeconds,
                  timeZoneIdentifier: focus.timeZoneIdentifier ?? TimeZone.current.identifier,
                  outcome: focus.outcome ?? .completed)
    }

    /// Everything saved about the session, e.g. to put it back after a delete.
    var completedFocus: CompletedFocus {
        CompletedFocus(id: id, name: name, startedAt: startedAt, completedAt: completedAt, focusSeconds: focusSeconds,
                       plannedSeconds: plannedSeconds, outcome: outcomeRaw.flatMap(FocusOutcome.init(rawValue:)),
                       timeZoneIdentifier: timeZoneIdentifier)
    }
}
