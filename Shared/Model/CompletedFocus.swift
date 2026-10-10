import Foundation

/// A finished focus phase on its way into History. Kept in the saved session
/// state until the store has it, so a failed save never loses a session.
struct CompletedFocus: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date
    var focusSeconds: TimeInterval
}
