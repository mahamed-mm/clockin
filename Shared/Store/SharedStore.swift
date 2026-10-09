import Foundation
import SwiftData

/// On-device storage shared between the app and the widget extension.
enum SharedStore {
    static let appGroup = "group.com.moha.clockin"

    nonisolated(unsafe) static let defaults: UserDefaults =
        UserDefaults(suiteName: appGroup) ?? .standard

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([FocusRecord.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url = containerURL?.appending(path: "Clockin.store") {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// What the engine persists so a running timer can be restored after relaunch.
struct PersistedSessionState: Codable, Equatable, Sendable {
    var active: ActiveSession?
    /// Set after a focus phase completes, until a break starts or the user moves on.
    var completedFocusName: String?
}

protocol SessionStateStoring {
    func load() -> PersistedSessionState
    func save(_ state: PersistedSessionState)
}

struct DefaultsSessionStateStore: SessionStateStoring {
    var defaults: UserDefaults = SharedStore.defaults
    var key = "session.state.v1"

    func load() -> PersistedSessionState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(PersistedSessionState.self, from: data)
        else { return PersistedSessionState() }
        return state
    }

    func save(_ state: PersistedSessionState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
}

final class InMemorySessionStateStore: SessionStateStoring {
    var state = PersistedSessionState()
    func load() -> PersistedSessionState { state }
    func save(_ state: PersistedSessionState) { self.state = state }
}
