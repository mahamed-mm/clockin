import Foundation

/// A stray thought put aside during focus, to come back to later. It stays
/// on this iPhone: never on the Lock Screen, in a widget or the Live
/// Activity, and never sent to the on-device model.
struct ParkedThought: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var parkedAt: Date
    /// Ticked off afterwards. Nil until then, and from older builds.
    var done: Bool? = nil

    /// One line, at most this long.
    static let maxLength = 200

    /// Trimmed, on one line and capped; nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        let line = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}
