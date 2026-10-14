import Foundation

/// A break that ran to its end, just now: the app says "Break's over" and
/// names the next session for a little while, then goes back to plain
/// waiting. Only a break that ran out makes one; skipping it doesn't.
struct BreakOverMoment: Codable, Equatable, Sendable {
    /// When the break ran out.
    var endedAt: Date
    /// The session the break followed, for the next one.
    var name: String
    /// It was the long break after a set of four.
    var wasLong: Bool

    /// How long the moment lasts (unless a session starts, a length is
    /// chosen, or the day ends first).
    static let window: TimeInterval = 10 * 60

    /// Still worth saying at `date`: within the window, on the same day.
    func isShowing(at date: Date, calendar: Calendar) -> Bool {
        Freshness.of(endedAt: endedAt, now: date, recentWindow: Self.window, calendar: calendar) != .stale
    }

    /// When it stops showing on its own: the window's end, or midnight.
    func ends(calendar: Calendar) -> Date {
        let midnight = calendar.dateInterval(of: .day, for: endedAt)?.end ?? endedAt.addingTimeInterval(Self.window)
        return min(endedAt.addingTimeInterval(Self.window), midnight)
    }

    /// Which session of the set comes next, from 1: after a long break, the first of a new set.
    static func nextPosition(fullToday: Int) -> Int {
        fullToday % TimerPlan.sessionsPerSet + 1
    }
}
