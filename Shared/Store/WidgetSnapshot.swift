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
    }

    /// Sessions that finished on the day the snapshot was written.
    var sessions: [Session]
    var writtenAt: Date

    init(rows: [TodayStats.Row], writtenAt: Date) {
        sessions = rows.map { Session(id: $0.id, completedAt: $0.completedAt, seconds: $0.seconds) }
        self.writtenAt = writtenAt
    }

    var rows: [TodayStats.Row] {
        sessions.map { (id: $0.id, completedAt: $0.completedAt, seconds: $0.seconds) }
    }

    /// The widget's numbers at `date`. Sessions from another day drop out, so a
    /// snapshot written before midnight reads as zero after it. A focus phase
    /// that ran out while the app was suspended counts before the app records it.
    func stats(at date: Date, active: ActiveSession?, calendar: Calendar = .autoupdatingCurrent) -> TodayStats {
        TodayStats.make(records: rows, unrecordedActive: active, now: date, calendar: calendar)
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
