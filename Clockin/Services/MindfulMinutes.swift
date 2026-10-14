import Foundation
import HealthKit

/// Whether Clockin may write to Health.
enum HealthPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// What AppServices needs from Health, so tests can stand in for it.
@MainActor
protocol MindfulLogging: AnyObject {
    var permission: HealthPermission { get }
    /// Asks the first time; afterwards just says what was chosen.
    func requestPermission() async -> HealthPermission
    /// Writes a finished session as Mindful Minutes, replacing any earlier
    /// sample for it (e.g. before kept overtime).
    func save(_ focus: CompletedFocus)
    /// Takes these sessions' samples out of Health.
    func remove(ids: [UUID])
    /// Takes every sample Clockin wrote out of Health.
    func removeAll()
    /// Retries writes still waiting and waits for those in flight.
    func flush() async
}

/// Finished focus sessions in Health as Mindful Minutes. Write-only: nothing
/// is read. Health can't be written while the phone is locked (a session can
/// finish on the Lock Screen alarm), so writes wait in a small queue in the
/// App Group and go when the app next runs unlocked.
@MainActor
final class MindfulMinutes: MindfulLogging {
    /// One session's sample, as it waits to be written.
    struct Pending: Codable, Equatable {
        var id: UUID
        var start: Date
        var end: Date
    }

    private nonisolated static let store = HKHealthStore()
    private nonisolated static var mindful: HKCategoryType { HKCategoryType(.mindfulSession) }
    private let defaults: UserDefaults
    private let key = "health.pending.v1"
    private var inFlight: Task<Void, Never>?

    init(defaults: UserDefaults = SharedStore.defaults) {
        self.defaults = defaults
    }

    var permission: HealthPermission {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        return switch Self.store.authorizationStatus(for: Self.mindful) {
        case .sharingAuthorized: .authorized
        case .sharingDenied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestPermission() async -> HealthPermission {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        do {
            try await Self.askForPermission()
        } catch {
            Log.store.error("Health authorization failed: \(error, privacy: .public)")
        }
        return permission
    }

    func save(_ focus: CompletedFocus) {
        guard focus.focusSeconds >= 1 else { return }
        var queue = pending.filter { $0.id != focus.id }
        // Pauses aren't counted, so the sample is the focus time ending when it finished.
        queue.append(Pending(id: focus.id, start: focus.completedAt.addingTimeInterval(-focus.focusSeconds),
                             end: focus.completedAt))
        pending = queue
        writePending()
    }

    func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        pending = pending.filter { !ids.contains($0.id) }
        let values = ids.map(\.uuidString)
        Task {
            do {
                try await Self.delete(HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                                  allowedValues: values))
            } catch {
                Log.store.error("Couldn't remove sessions from Health: \(error, privacy: .public)")
            }
        }
    }

    func removeAll() {
        pending = []
        Task {
            do {
                try await Self.delete(HKQuery.predicateForObjects(from: .default()))
            } catch {
                Log.store.error("Couldn't remove Clockin's sessions from Health: \(error, privacy: .public)")
            }
        }
    }

    func flush() async {
        if inFlight == nil, !pending.isEmpty { writePending() }
        await inFlight?.value
    }

    // MARK: Queue

    /// Writes still waiting, kept across launches.
    var pending: [Pending] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: key)
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }

    /// Writes what's queued, one after another; what fails stays for next time.
    private func writePending() {
        guard permission == .authorized else { return }
        let previous = inFlight
        inFlight = Task {
            await previous?.value
            for item in pending {
                do {
                    try await Self.write(item)
                    pending = pending.filter { $0 != item }
                } catch {
                    Log.store.info("Health write waits for later: \(error, privacy: .public)")
                    break
                }
            }
            inFlight = nil
        }
    }

    // HKHealthStore's async calls are made away from the main actor.

    @concurrent
    private nonisolated static func askForPermission() async throws {
        try await store.requestAuthorization(toShare: [mindful], read: [])
    }

    /// Replaces the session's sample, so writing it twice never counts twice.
    @concurrent
    private nonisolated static func write(_ item: Pending) async throws {
        let mine = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                               allowedValues: [item.id.uuidString])
        try await delete(mine)
        let sample = HKCategorySample(type: mindful, value: HKCategoryValue.notApplicable.rawValue,
                                      start: item.start, end: item.end,
                                      metadata: [HKMetadataKeyExternalUUID: item.id.uuidString])
        try await store.save(sample)
    }

    @concurrent
    private nonisolated static func delete(_ predicate: NSPredicate) async throws {
        _ = try await store.deleteObjects(of: mindful, predicate: predicate)
    }
}

/// No Health, for previews and for tests that don't care about it.
@MainActor
final class NoMindfulLog: MindfulLogging {
    var permission: HealthPermission { .notDetermined }
    func requestPermission() async -> HealthPermission { .notDetermined }
    func save(_ focus: CompletedFocus) {}
    func remove(ids: [UUID]) {}
    func removeAll() {}
    func flush() async {}
}
