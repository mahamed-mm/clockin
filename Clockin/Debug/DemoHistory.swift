#if DEBUG
import Foundation

/// Six believable weeks of focus, for screenshots: recurring names, busy
/// weekdays and quiet weekends, a few empty days, one long day, an early
/// and a late session, and two that ended early. The same `now` always gives
/// the same sessions.
enum DemoHistory {
    struct Session: Equatable {
        var name: String
        var startedAt: Date
        var completedAt: Date
        var focusSeconds: TimeInterval
        var plannedSeconds: TimeInterval
        var outcome: FocusOutcome = .completed
    }

    static let names = ["Chemistry", "Spanish vocab", "Thesis outline", "Linear algebra",
                        "Reading: Dune", "Journaling", "Piano practice", "Emails"]
    /// Today's plan, as `-DemoData` sets it: the first one done this morning.
    static let plan = ["Chemistry", "Thesis outline", "Linear algebra", "Piano practice"]
    /// Symbols picked by hand: one overriding its suggestion, one the same as it.
    static let picks = ["Thesis outline": "pencil", "Emails": "envelope.fill"]

    private static let weeks = 6
    private static let minute: TimeInterval = 60

    static func make(now: Date, calendar: Calendar) -> [Session] {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? today
        var sessions: [Session] = []
        var day = first
        while day < today {
            let back = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            sessions += self.day(day, daysBack: back, calendar: calendar)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
        }
        // Earlier today, ending well before now.
        for (slot, endsAgo) in [100.0, 65, 30].enumerated() {
            let end = now.addingTimeInterval(-endsAgo * minute)
            let start = end.addingTimeInterval(-25 * minute)
            guard start >= today else { continue }
            sessions.append(Session(name: ["Chemistry", "Reading: Dune", "Spanish vocab"][slot], startedAt: start,
                                    completedAt: end, focusSeconds: 25 * minute, plannedSeconds: 25 * minute))
        }
        return sessions
    }

    /// One past day, `daysBack` before today.
    private static func day(_ day: Date, daysBack: Int, calendar: Calendar) -> [Session] {
        var random = Random(seed: UInt64(daysBack))
        let weekend = calendar.isDateInWeekend(day)
        var count = weekend ? random.next(in: 0...2) : random.next(in: 2...6)
        if !weekend, random.unit() < 0.12 { count = 0 } // A day off.
        if daysBack == 9 { count = 6 } // A long day, past a set of four.

        var sessions: [Session] = []
        var start = day.addingTimeInterval(TimeInterval(random.next(in: 8...10)) * 3_600
                                           + TimeInterval(random.next(in: 0...5) * 10) * minute)
        if daysBack == 4 { // Up early, and stopped past half the plan, so it still counts.
            var early = session("Journaling", from: day.addingTimeInterval(5 * 3_600 + 40 * minute),
                                planned: 25 * minute)
            endEarly(&early, fraction: 0.6)
            sessions.append(early)
        }
        let latest = day.addingTimeInterval(21 * 3_600 + 30 * minute)
        for _ in 0..<count {
            let planned = [25.0, 25, 25, 50, 15][random.next(in: 0...4)] * minute
            guard start.addingTimeInterval(planned) <= latest else { break }
            let name = names[random.next(in: 0...(names.count - 1))]
            sessions.append(session(name, from: start, planned: planned))
            start = start.addingTimeInterval(planned + TimeInterval(random.next(in: 1...7) * 5) * minute)
        }
        if daysBack == 2 { // Up late, and stopped short of half the plan, so it doesn't count.
            var late = session("Reading: Dune", from: day.addingTimeInterval(22 * 3_600 + 30 * minute),
                               planned: 25 * minute)
            endEarly(&late, fraction: 0.3)
            sessions.append(late)
        }
        return sessions
    }

    private static func session(_ name: String, from start: Date, planned: TimeInterval) -> Session {
        Session(name: name, startedAt: start, completedAt: start.addingTimeInterval(planned), focusSeconds: planned,
                plannedSeconds: planned)
    }

    private static func endEarly(_ session: inout Session, fraction: Double) {
        session.focusSeconds = (session.plannedSeconds * fraction).rounded()
        session.completedAt = session.startedAt.addingTimeInterval(session.focusSeconds)
        session.outcome = .endedEarly
    }

    /// A small, fixed generator (SplitMix64), so a day's sessions never change.
    private struct Random {
        var state: UInt64

        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

        mutating func next(in range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
    }
}
#endif
