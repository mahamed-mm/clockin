import Foundation
import SwiftData

/// On-device storage shared between the app and the widget extension.
enum SharedStore {
    /// From the `APP_GROUP_ID` build setting, via each target's Info.plist.
    static let appGroup: String = {
        let id = Bundle.main.object(forInfoDictionaryKey: "ClockinAppGroup") as? String
        assert(id?.isEmpty == false, "ClockinAppGroup is missing from Info.plist; check APP_GROUP_ID in project.yml")
        return id ?? "group.com.moha.clockin"
    }()

    nonisolated(unsafe) static let defaults: UserDefaults =
        UserDefaults(suiteName: appGroup) ?? .standard

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    enum StoreError: Error {
        /// The App Group container doesn't exist, almost always a missing
        /// application-groups entitlement. Writing anywhere else would hide
        /// History from the widget, so this fails loudly instead.
        case noAppGroupContainer
    }

    /// Opens the history store through the migration plan. `url` overrides the
    /// App Group location (tests); `inMemory` keeps nothing on disk. `readOnly`
    /// is for the widget: it can't save, so it can never migrate the store
    /// out from under the app.
    static func makeModelContainer(inMemory: Bool = false, url: URL? = nil,
                                   readOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ClockinSchemaV2.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            guard let url = url ?? containerURL?.appending(path: "Clockin.store") else {
                assertionFailure("No App Group container for \(appGroup); check the application-groups entitlement")
                throw StoreError.noAppGroupContainer
            }
            // Sync stays off explicitly: the default would turn it on if an
            // iCloud entitlement were ever added.
            config = ModelConfiguration(schema: schema, url: url, allowsSave: !readOnly, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: ClockinMigrationPlan.self, configurations: [config])
    }
}

/// What the engine persists so a running timer can be restored after relaunch.
///
/// Decoding rule: every field added after 1.0 must be Optional (or decoded
/// with a default), so state written by an older build always loads.
struct PersistedSessionState: Codable, Equatable, Sendable {
    static let currentFormat = 3

    var active: ActiveSession?
    /// Set after a focus phase completes, until a break starts or the user moves on. (Format 3.)
    var completedFocus: CompletedFocus?
    /// What formats 1 and 2 kept instead of `completedFocus`. Read, never written.
    var completedFocusName: String?
    /// Finished sessions the store couldn't take yet; retried on reconcile. (Format 2.)
    var pendingRecords: [CompletedFocus]?
    /// The format that wrote this. Missing means format 1 (1.0).
    var format: Int? = PersistedSessionState.currentFormat
}

protocol SessionStateStoring {
    func load() -> PersistedSessionState
    func save(_ state: PersistedSessionState)
}

struct DefaultsSessionStateStore: SessionStateStoring {
    var defaults: UserDefaults = SharedStore.defaults
    var key = "session.state.v1"

    /// Where state that can't be decoded is kept, so the next save can't destroy it.
    var unreadableKey: String { key + ".unreadable" }

    func load() -> PersistedSessionState {
        guard let data = defaults.data(forKey: key) else { return PersistedSessionState() }
        do {
            return try JSONDecoder().decode(PersistedSessionState.self, from: data)
        } catch {
            Log.store.error("Saved session state is unreadable; starting idle and keeping a copy: \(error, privacy: .public)")
            defaults.set(data, forKey: unreadableKey)
            return PersistedSessionState()
        }
    }

    func save(_ state: PersistedSessionState) {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: key)
        } catch {
            Log.store.error("Couldn't encode session state: \(error, privacy: .public)")
        }
    }
}

final class InMemorySessionStateStore: SessionStateStoring {
    var state = PersistedSessionState()
    func load() -> PersistedSessionState { state }
    func save(_ state: PersistedSessionState) { self.state = state }
}
