import Foundation
import SwiftData

/// A completed focus phase. Breaks and cancelled sessions are never stored.
@Model
final class FocusRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date
    var focusSeconds: Double

    init(id: UUID, name: String, startedAt: Date, completedAt: Date, focusSeconds: Double) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.focusSeconds = focusSeconds
    }
}
