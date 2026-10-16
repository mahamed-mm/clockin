import Foundation

/// Where to go in History: one subject's page, opened from a row that it
/// can zoom out of.
struct SubjectRoute: Hashable {
    /// `SymbolBook.key`: every spelling of the name.
    var key: String
    /// As the newest session spells it.
    var name: String
    /// The view the page zooms out of, if any: a By subject row, or the
    /// session row a card or a menu was opened from.
    var zoomFrom: AnyHashable?

    /// The By subject row's zoom source.
    static func rowSource(_ key: String) -> AnyHashable { "subject:" + key }

    /// What the page zooms out of: nothing with Reduce Motion, which
    /// pushes it plainly.
    func zoomSource(reduceMotion: Bool) -> AnyHashable? { reduceMotion ? nil : zoomFrom }
}

/// Everything saved under one subject (a name, matched the way symbols are,
/// ignoring case, width and extra spaces), as facts: how much, since when,
/// when in the day and how long, the latest sessions, the last three
/// months. Never a best, a streak or a comparison. Pure, so it can be tested.
struct SubjectHistory: Equatable {
    struct Session: Equatable, Identifiable {
        var id: UUID
        var name: String
        var startedAt: Date
        var completedAt: Date
        var seconds: TimeInterval
        var plannedSeconds: TimeInterval?
    }

    /// How many recent sessions the page lists.
    static let recentCount = 8
    /// How many months it shows, this one included.
    static let monthCount = 3

    let key: String
    /// Newest first.
    let sessions: [Session]

    init(key: String, sessions: [Session]) {
        self.key = key
        self.sessions = sessions.filter { SymbolBook.key(for: $0.name) == key }
            .sorted { $0.completedAt > $1.completedAt }
    }

    /// As the newest session spells it.
    var name: String { sessions.first?.name ?? key }
    var totalSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.seconds } }
    var sessionCount: Int { sessions.count }
    var firstDate: Date? { sessions.last?.completedAt }
    var recent: [Session] { Array(sessions.prefix(Self.recentCount)) }
    /// What it was last planned for, for Start again.
    var lastPlanned: TimeInterval? { sessions.first?.plannedSeconds }

    /// The part of the day most of its focus started in, when one had at
    /// least 60% of it: the same rule as the week's line.
    func usualPart(calendar: Calendar) -> WeekFacts.PartOfDay? {
        WeekFacts(sessions: sessions.map {
            WeekFacts.Session(startedAt: $0.startedAt, completedAt: $0.completedAt, seconds: $0.seconds)
        }, calendar: calendar)?.mostlyIn
    }

    /// How long a session of it usually runs: the median, to the nearest
    /// five minutes, never under five.
    var typicalLength: TimeInterval? {
        let lengths = sessions.map(\.seconds).filter { $0 > 0 }.sorted()
        guard !lengths.isEmpty else { return nil }
        let middle = lengths.count / 2
        let median = lengths.count.isMultiple(of: 2) ? (lengths[middle - 1] + lengths[middle]) / 2 : lengths[middle]
        let step: TimeInterval = 5 * 60
        return max(step, (median / step).rounded() * step)
    }

    /// The last three months, this one first, each as its days with this
    /// subject's sessions in them.
    func months(endingAt today: Date, calendar: Calendar) -> [(month: DateInterval, days: [Date: DayTotal])] {
        let thisMonth = calendar.monthInterval(containing: today)
        return (0..<Self.monthCount).compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth.start) else { return nil }
            let month = calendar.monthInterval(containing: start)
            var days: [Date: DayTotal] = [:]
            for session in sessions where month.contains(session.completedAt) && session.completedAt < month.end {
                let day = calendar.startOfDay(for: session.completedAt)
                var total = days[day] ?? DayTotal(day: day, seconds: 0, sessions: 0)
                total.seconds += session.seconds
                total.sessions += 1
                days[day] = total
            }
            return (month, days)
        }
    }
}
