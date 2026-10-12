import Foundation
import SwiftData

/// Saves completed focus sessions. Recording is idempotent by session id, and
/// throws when the session wasn't saved so the engine can keep it for later.
@MainActor
protocol FocusLogging {
    func record(_ focus: CompletedFocus) throws
    /// Saved sessions that finished on the day containing `day`.
    func sessions(on day: Date, calendar: Calendar) throws -> [FocusRow]
}

@MainActor
final class SwiftDataFocusLog: FocusLogging {
    /// Held so the store stays open: a context doesn't keep its container alive.
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    func record(_ focus: CompletedFocus) throws {
        let id = focus.id
        var existing = FetchDescriptor<FocusRecord>(predicate: #Predicate { $0.id == id })
        existing.fetchLimit = 1
        if try context.fetchCount(existing) > 0 { return }
        context.insert(FocusRecord(id: focus.id, name: focus.name, startedAt: focus.startedAt,
                                   completedAt: focus.completedAt, focusSeconds: focus.focusSeconds,
                                   plannedSeconds: focus.plannedSeconds,
                                   timeZoneIdentifier: focus.timeZoneIdentifier ?? TimeZone.current.identifier,
                                   outcome: focus.outcome ?? .completed))
        do {
            try context.save()
        } catch {
            // Drop the unsaved insert so a later retry starts clean.
            context.rollback()
            throw error
        }
    }

    func sessions(on day: Date, calendar: Calendar) throws -> [FocusRow] {
        try context.fetch(FetchDescriptor(predicate: FocusRecord.completed(on: day, calendar: calendar))).map(\.row)
    }
}

/// Stands in when the store couldn't be opened: every save fails, so finished
/// sessions stay pending in the session state instead of vanishing into memory.
struct UnavailableFocusLog: FocusLogging {
    struct StoreUnavailable: Error {}

    func record(_ focus: CompletedFocus) throws {
        throw StoreUnavailable()
    }

    /// Nothing saved can be read; sessions waiting to be saved still count.
    func sessions(on day: Date, calendar: Calendar) throws -> [FocusRow] { [] }
}
