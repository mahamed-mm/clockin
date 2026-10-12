import Foundation
import SwiftData

/// Version 1 of the on-disk model, as shipped in 1.0.
///
/// To change the model: add a `ClockinSchemaV(n+1)` with the new attributes,
/// point the `FocusRecord` typealias at it, and add it plus a migration stage
/// to `ClockinMigrationPlan`. Never edit a shipped version.
enum ClockinSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [FocusRecord.self] }
}

/// Version 2: planned length, time zone and outcome, all optional, so 1.0's
/// sessions carry over untouched.
enum ClockinSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [FocusRecord.self] }
}

/// Every schema version in order, and how to move between them. Only the app
/// migrates: the widget opens the store read-only, which can't.
enum ClockinMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ClockinSchemaV1.self, ClockinSchemaV2.self] }
    static var stages: [MigrationStage] {
        // New optional attributes only, so SwiftData can do it alone.
        [.lightweight(fromVersion: ClockinSchemaV1.self, toVersion: ClockinSchemaV2.self)]
    }
}
