import Foundation
import SwiftData

/// Version 1 of the on-disk model, as shipped in 1.0.
///
/// To change the model: copy this enum to `ClockinSchemaV2` with the new
/// attributes, point the `FocusRecord` typealias at it, and add V2 plus a
/// migration stage to `ClockinMigrationPlan`. Never edit a shipped version.
enum ClockinSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [FocusRecord.self] }
}

/// Every schema version in order, and how to move between them. Shared by
/// the app and the widget, so whichever opens the store first upgrades it.
enum ClockinMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ClockinSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
