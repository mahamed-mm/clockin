import Foundation
import SwiftData

/// The current model. Code uses this name; the versioned schema owns the type.
typealias FocusRecord = ClockinSchemaV1.FocusRecord

extension ClockinSchemaV1 {
    /// A completed focus phase. Breaks and cancelled sessions are never stored.
    ///
    /// Frozen: this is exactly the model 1.0 shipped with, so existing stores
    /// open without a migration. New attributes go in a new schema version.
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
}
