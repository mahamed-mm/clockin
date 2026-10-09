import Foundation
import SwiftData

/// Saves completed focus sessions. Recording is idempotent by session id.
@MainActor
protocol FocusLogging {
    func record(id: UUID, name: String, startedAt: Date, completedAt: Date, focusSeconds: TimeInterval)
    func records(on day: Date, calendar: Calendar) -> [FocusRecord]
}

@MainActor
final class SwiftDataFocusLog: FocusLogging {
    let context: ModelContext

    init(container: ModelContainer) {
        context = container.mainContext
    }

    func record(id: UUID, name: String, startedAt: Date, completedAt: Date, focusSeconds: TimeInterval) {
        var existing = FetchDescriptor<FocusRecord>(predicate: #Predicate { $0.id == id })
        existing.fetchLimit = 1
        if let count = try? context.fetchCount(existing), count > 0 { return }
        context.insert(FocusRecord(id: id, name: name, startedAt: startedAt,
                                   completedAt: completedAt, focusSeconds: focusSeconds))
        try? context.save()
    }

    func records(on day: Date, calendar: Calendar = .current) -> [FocusRecord] {
        TodayStats.fetchRecords(on: day, calendar: calendar, context: context)
    }
}
