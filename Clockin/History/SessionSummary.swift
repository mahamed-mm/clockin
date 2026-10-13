import Foundation

/// What the session card says about one saved session. Plain values copied
/// from the record, so the card outlives a delete and the wording can be
/// tested without SwiftData.
struct SessionSummary: Identifiable, Equatable {
    struct Row: Hashable {
        let label: String
        let value: String
    }

    let id: UUID
    let name: String
    let startedAt: Date
    let completedAt: Date
    let focusSeconds: TimeInterval
    /// Nil for sessions saved by 1.x.
    let plannedSeconds: TimeInterval?
    let outcome: FocusOutcome

    init(id: UUID, name: String, startedAt: Date, completedAt: Date, focusSeconds: TimeInterval,
         plannedSeconds: TimeInterval?, outcome: FocusOutcome) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.focusSeconds = focusSeconds
        self.plannedSeconds = plannedSeconds
        self.outcome = outcome
    }

    init(_ record: FocusRecord) {
        self.init(id: record.id, name: record.name, startedAt: record.startedAt,
                  completedAt: record.completedAt, focusSeconds: record.focusSeconds,
                  plannedSeconds: record.plannedSeconds, outcome: record.outcome)
    }

    var title: String { Copy.displayName(name) }

    var countsAsFull: Bool {
        FocusRow.isFull(outcome: outcome, seconds: focusSeconds, planned: plannedSeconds)
    }

    /// "Today · 14:05 → 14:30"
    func overline(now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        "\(day(now: now, calendar: calendar)) · \(TimeFormat.range(startedAt, completedAt))"
    }

    /// "Today, 14:05 to 14:30": the arrow reads badly aloud.
    func spokenOverline(now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        String(localized: """
            \(day(now: now, calendar: calendar)), \(TimeFormat.time(startedAt)) to \(TimeFormat.time(completedAt))
            """)
    }

    var rows: [Row] {
        var rows = [Row(label: String(localized: "Focused"), value: TimeFormat.duration(focusSeconds))]
        if let plannedSeconds {
            rows.append(Row(label: String(localized: "Planned"), value: TimeFormat.duration(plannedSeconds)))
        }
        rows.append(Row(label: String(localized: "Ended"),
                        value: outcome == .endedEarly ? String(localized: "Early, with Finish now")
                                                      : String(localized: "When time was up")))
        rows.append(Row(label: String(localized: "Set of four"),
                        value: countsAsFull ? String(localized: "Counts")
                                            : String(localized: "Under half its plan")))
        return rows
    }

    private func day(now: Date, calendar: Calendar) -> String {
        if calendar.isDate(completedAt, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(completedAt, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return completedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
