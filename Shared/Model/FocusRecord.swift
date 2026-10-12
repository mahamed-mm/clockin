import Foundation
import SwiftData

/// The current model. Code uses this name; the versioned schema owns the type.
typealias FocusRecord = ClockinSchemaV2.FocusRecord

/// How a focus session ended. Stored as its raw value, so a value from a
/// newer build reads as `.completed` instead of failing.
enum FocusOutcome: String, Codable, Sendable {
    /// Ran to the end of its plan (with any minutes added along the way).
    case completed
    /// Finished early with "Finish now"; its minutes still count.
    case endedEarly
}

extension ClockinSchemaV2 {
    /// A completed focus phase. Breaks and cancelled sessions are never stored.
    /// Frozen once shipped; new attributes go in a new schema version.
    @Model
    final class FocusRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var startedAt: Date
        var completedAt: Date
        var focusSeconds: Double
        /// The length planned at start. Nil for sessions saved by 1.x.
        var plannedSeconds: Double?
        /// Where it happened, so a day can be read in its own time zone. Nil for 1.x.
        var timeZoneIdentifier: String?
        /// `FocusOutcome` raw value. Nil for 1.x, which only kept completed sessions.
        var outcomeRaw: String?

        init(id: UUID, name: String, startedAt: Date, completedAt: Date, focusSeconds: Double,
             plannedSeconds: Double? = nil, timeZoneIdentifier: String? = nil, outcome: FocusOutcome? = nil) {
            self.id = id
            self.name = name
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.focusSeconds = focusSeconds
            self.plannedSeconds = plannedSeconds
            self.timeZoneIdentifier = timeZoneIdentifier
            self.outcomeRaw = outcome?.rawValue
        }

        var outcome: FocusOutcome {
            outcomeRaw.flatMap(FocusOutcome.init(rawValue:)) ?? .completed
        }
    }
}

extension ClockinSchemaV1 {
    /// Exactly the model 1.0 shipped with. Never edit: migrations start here.
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
