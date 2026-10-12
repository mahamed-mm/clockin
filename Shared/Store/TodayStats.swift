import Foundation
import SwiftData

/// One finished focus session, saved or still waiting to be saved: just
/// what the totals need.
struct FocusRow: Equatable, Sendable {
    var id: UUID
    var completedAt: Date
    var seconds: TimeInterval
    /// Fills a session pill. Every minute counts toward time focused, but a
    /// session finished early only fills a pill at half its plan or more.
    var countsAsFull: Bool

    init(id: UUID = UUID(), completedAt: Date, seconds: TimeInterval, countsAsFull: Bool = true) {
        self.id = id
        self.completedAt = completedAt
        self.seconds = seconds
        self.countsAsFull = countsAsFull
    }

    /// The one rule for what fills a pill, used everywhere sessions are counted.
    static func isFull(outcome: FocusOutcome, seconds: TimeInterval, planned: TimeInterval?) -> Bool {
        guard outcome == .endedEarly, let planned, planned > 0 else { return true }
        return seconds >= planned / 2
    }
}

extension [FocusRow] {
    /// Sessions that fill a pill.
    var fullCount: Int { count { $0.countsAsFull } }
    var totalSeconds: TimeInterval { reduce(0) { $0 + $1.seconds } }
}

/// Today's completed focus, shared by the Focus screen, History, and the widget.
struct TodayStats: Equatable, Sendable {
    var focusSeconds: TimeInterval
    var sessionCount: Int

    static let empty = TodayStats(focusSeconds: 0, sessionCount: 0)

    var focusMinutes: Int { Int((focusSeconds / 60).rounded(.down)) }

    /// Saved rows plus sessions still waiting to be saved, each counted once,
    /// so a session the app is keeping never drops out of the totals.
    static func rows(saved: [FocusRow], pending: [CompletedFocus]) -> [FocusRow] {
        let savedIDs = Set(saved.map(\.id))
        return saved + pending.filter { !savedIDs.contains($0.id) }.map(\.row)
    }

    /// Builds stats from saved records and waiting ones, plus a focus phase that
    /// has finished but not been recorded yet (e.g. the app was suspended when it ended).
    static func make(records: [FocusRow],
                     pending: [CompletedFocus] = [],
                     unrecordedActive: ActiveSession?,
                     now: Date,
                     calendar: Calendar = .current) -> TodayStats {
        var seconds: TimeInterval = 0
        var count = 0
        var seen = Set<UUID>()
        for r in rows(saved: records, pending: pending) where calendar.isDate(r.completedAt, inSameDayAs: now) {
            seconds += r.seconds
            if r.countsAsFull { count += 1 }
            seen.insert(r.id)
        }
        if let active = unrecordedActive, active.phase == .focus,
           let end = active.endDate, end <= now,
           calendar.isDate(end, inSameDayAs: now), !seen.contains(active.id) {
            seconds += active.plannedDuration
            count += 1
        }
        return TodayStats(focusSeconds: seconds, sessionCount: count)
    }

    static func fetchRecords(on day: Date, calendar: Calendar, context: ModelContext) -> [FocusRecord] {
        let descriptor = FetchDescriptor<FocusRecord>(
            predicate: FocusRecord.completed(on: day, calendar: calendar),
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

extension FocusRecord {
    var row: FocusRow {
        FocusRow(id: id, completedAt: completedAt, seconds: focusSeconds,
                 countsAsFull: FocusRow.isFull(outcome: outcome, seconds: focusSeconds, planned: plannedSeconds))
    }

    /// Records completed on the day containing `day`, for fetches and `@Query`.
    static func completed(on day: Date, calendar: Calendar = .autoupdatingCurrent) -> Predicate<FocusRecord> {
        let range = calendar.dayRange(containing: day)
        let start = range.lowerBound
        let end = range.upperBound
        return #Predicate { $0.completedAt >= start && $0.completedAt < end }
    }
}

extension Calendar {
    /// The day containing `date`, from its first moment up to the next day's.
    /// Unlike adding 86 400 s, this is right on the 23- and 25-hour days when
    /// the clocks change.
    func dayRange(containing date: Date) -> Range<Date> {
        if let day = dateInterval(of: .day, for: date) { return day.start..<day.end }
        let start = startOfDay(for: date)
        return start..<(self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }
}

/// One day's focus in the History week strip.
struct DayTotal: Equatable, Sendable {
    var day: Date
    var seconds: TimeInterval
    var sessions: Int
}

extension TodayStats {
    /// Focus seconds and full sessions for each day of the week containing
    /// `day`, in the calendar's week order (e.g. Mon–Sun).
    static func weekTotals(records: [FocusRow],
                           containing day: Date,
                           calendar: Calendar = .current) -> [DayTotal] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return [] }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        return days.map { start in
            let sameDay = records.filter { calendar.isDate($0.completedAt, inSameDayAs: start) }
            return DayTotal(day: start, seconds: sameDay.totalSeconds, sessions: sameDay.fullCount)
        }
    }
}
