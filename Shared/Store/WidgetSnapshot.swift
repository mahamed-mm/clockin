import Foundation

/// Today's finished focus as the app last saw it, written to the App Group on
/// every session event and history change. The Home Screen widget reads this
/// instead of opening the history store, so it stays light and can never
/// migrate the store out from under the app.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// One finished focus session, saved or still waiting to be saved.
    struct Session: Codable, Equatable, Sendable {
        var id: UUID
        var completedAt: Date
        var seconds: TimeInterval
        /// Nil in snapshots written before sessions could end early: full.
        var countsAsFull: Bool?
        /// For the large widget's list. Nil in older snapshots.
        var name: String?
        var symbol: String?
        var startedAt: Date?
    }

    /// One day of the week, for the large widget's strip.
    struct Day: Codable, Equatable, Sendable {
        var day: Date
        var seconds: TimeInterval
        var sessions: Int
    }

    /// Sessions that finished on the day the snapshot was written.
    var sessions: [Session]
    var writtenAt: Date
    /// The week the snapshot was written in. Nil in older snapshots.
    var week: [Day]?
    /// The next planned session, for the large widget. Nil without a plan
    /// and in older snapshots.
    var next: NextUp?

    /// The next planned session at `date`: only on the day it was planned.
    func next(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> NextUp? {
        calendar.isDate(writtenAt, inSameDayAs: date) ? next : nil
    }

    init(rows: [FocusRow], writtenAt: Date) {
        sessions = rows.map {
            Session(id: $0.id, completedAt: $0.completedAt, seconds: $0.seconds, countsAsFull: $0.countsAsFull)
        }
        self.writtenAt = writtenAt
    }

    init(sessions: [Session], week: [DayTotal]?, writtenAt: Date) {
        self.sessions = sessions
        self.week = week?.map { Day(day: $0.day, seconds: $0.seconds, sessions: $0.sessions) }
        self.writtenAt = writtenAt
    }

    var rows: [FocusRow] {
        sessions.map {
            FocusRow(id: $0.id, completedAt: $0.completedAt, seconds: $0.seconds, countsAsFull: $0.countsAsFull ?? true)
        }
    }

    /// The widget's numbers at `date`. Sessions from another day drop out, so a
    /// snapshot written before midnight reads as zero after it. A focus phase
    /// that ran out while the app was suspended counts before the app records it.
    func stats(at date: Date, active: ActiveSession?, calendar: Calendar = .autoupdatingCurrent) -> TodayStats {
        TodayStats.make(records: rows, unrecordedActive: active, now: date, calendar: calendar)
    }

    /// The week strip at `date`: the snapshot's week with today's column as
    /// of `date`, or, once a new week has begun without the app, a fresh one
    /// with only today filled in.
    func week(at date: Date, active: ActiveSession?, calendar: Calendar = .autoupdatingCurrent) -> [DayTotal] {
        let interval = calendar.weekInterval(containing: date)
        let saved = (week ?? []).filter { interval.includes($0.day) }
        let today = stats(at: date, active: active, calendar: calendar)
        var day = interval.start
        var days: [DayTotal] = []
        while day < interval.end {
            if calendar.isDate(day, inSameDayAs: date) {
                days.append(DayTotal(day: day, seconds: today.focusSeconds, sessions: today.sessionCount))
            } else if let known = saved.first(where: { calendar.isDate($0.day, inSameDayAs: day) }), day < date {
                days.append(DayTotal(day: day, seconds: known.seconds, sessions: known.sessions))
            } else {
                days.append(DayTotal(day: day, seconds: 0, sessions: 0))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Sessions finished on `date`'s day, newest first.
    func sessions(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> [Session] {
        sessions.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }
            .sorted { $0.completedAt > $1.completedAt }
    }

    /// When the widget's timeline redraws, ending at midnight: now, the
    /// running phase's end so the count updates without the app, and, with
    /// no session going, night starting or ending so Tick sleeps and wakes.
    /// Anything after midnight waits for the timeline that starts then.
    static func timelineDates(at now: Date, active: ActiveSession?, calendar: Calendar = .autoupdatingCurrent,
                              shift: TimeInterval = TimeFormat.demoShift) -> [Date] {
        let midnight = calendar.dayRange(containing: now).upperBound
        var changes: [Date]
        if let active, !active.isFinished(at: now) {
            changes = active.endDate.map { [$0] } ?? []
        } else {
            changes = TickPose.nightChanges(after: now, calendar: calendar, shift: shift)
        }
        return [now] + changes.filter { $0 > now && $0 < midnight }.sorted() + [midnight]
    }
}

struct WidgetSnapshotStore {
    var defaults: UserDefaults = SharedStore.defaults
    var key = "widget.snapshot.v1"

    /// Nil until the app has written one, e.g. on the first run after an update.
    func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            Log.store.error("Widget snapshot is unreadable: \(error, privacy: .public)")
            return nil
        }
    }

    func save(_ snapshot: WidgetSnapshot) {
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
        } catch {
            Log.store.error("Couldn't encode the widget snapshot: \(error, privacy: .public)")
        }
    }
}
