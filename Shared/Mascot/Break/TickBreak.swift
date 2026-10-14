import Foundation

/// What Tick's break needs from a running break: its length, its clock,
/// and how it's being spent since when. Everything else is worked out
/// from these at each frame, so a break opened mid-way, or come back to
/// from the background, shows exactly where it is.
struct TickBreak: Equatable, Sendable {
    /// The break's length.
    var planned: TimeInterval
    /// When it runs out, while running.
    var endDate: Date?
    /// The time left, frozen while paused.
    var pausedRemaining: TimeInterval?
    var style: BreakStyle
    /// How far into the break the style began, in the break's own time.
    var from: TimeInterval = 0

    var isPaused: Bool { endDate == nil }

    /// Like the session's own: never more than the length, never below 0.
    func remaining(at date: Date) -> TimeInterval {
        let left = endDate.map { $0.timeIntervalSince(date) } ?? pausedRemaining ?? planned
        return min(planned, max(0, left))
    }

    /// The break done by `date`, pauses not counted.
    func elapsed(at date: Date) -> TimeInterval { planned - remaining(at: date) }

    /// How long the current style has run by `date`.
    func styleElapsed(at date: Date) -> TimeInterval { max(0, elapsed(at: date) - from) }

    /// How long the style has from its start to the end of the break.
    var styleLength: TimeInterval { max(0, planned - from) }

    /// The moment the style has run `seconds`, while running.
    func date(atStyleElapsed seconds: TimeInterval) -> Date? {
        endDate?.addingTimeInterval(from + seconds - planned)
    }
}
