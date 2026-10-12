import Foundation

/// A finished focus phase on its way into History. Kept in the saved session
/// state until the store has it, so a failed save never loses a session.
struct CompletedFocus: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date
    var focusSeconds: TimeInterval
    /// Length of the break it earned, fixed when the focus phase started.
    /// Nil for completions saved by older builds.
    var breakSeconds: TimeInterval? = nil
    /// The length planned at start. Nil from older builds.
    var plannedSeconds: TimeInterval? = nil
    /// Nil from older builds, which only finished sessions by running out.
    var outcome: FocusOutcome? = nil

    /// Whether it fills a session pill and counts toward the set of four.
    var countsAsFull: Bool {
        FocusRow.isFull(outcome: outcome ?? .completed, seconds: focusSeconds, planned: plannedSeconds)
    }

    var row: FocusRow {
        FocusRow(id: id, completedAt: completedAt, seconds: focusSeconds, countsAsFull: countsAsFull)
    }
}
