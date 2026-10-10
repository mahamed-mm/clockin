import Foundation

enum SessionPhase: String, Codable, Hashable, Sendable {
    case focus
    case rest
}

/// The single in-progress session. Persisted so the timer survives relaunch.
/// Fields added after 1.0 must be Optional so older saved state still decodes.
struct ActiveSession: Codable, Equatable, Sendable {
    enum RunState: Equatable, Sendable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    var id: UUID
    var name: String
    var phase: SessionPhase
    var plannedDuration: TimeInterval
    /// When the focus phase began; used for the record's start time.
    var focusStartedAt: Date
    var state: RunState

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var endDate: Date? {
        if case .running(let end) = state { return end }
        return nil
    }

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let remaining): max(0, remaining)
        }
    }

    func progress(at now: Date) -> Double {
        guard plannedDuration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / plannedDuration))
    }

    func isFinished(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }
}

/// Hand-written so the saved keys can't drift if a case is renamed. Matches
/// what 1.0 wrote: `{"running":{"endDate":…}}` or `{"paused":{"remaining":…}}`.
extension ActiveSession.RunState: Codable {
    private enum CodingKeys: String, CodingKey { case running, paused }
    private enum RunningKeys: String, CodingKey { case endDate }
    private enum PausedKeys: String, CodingKey { case remaining }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.running) {
            let running = try container.nestedContainer(keyedBy: RunningKeys.self, forKey: .running)
            self = .running(endDate: try running.decode(Date.self, forKey: .endDate))
        } else if container.contains(.paused) {
            let paused = try container.nestedContainer(keyedBy: PausedKeys.self, forKey: .paused)
            self = .paused(remaining: try paused.decode(TimeInterval.self, forKey: .remaining))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                    debugDescription: "Unknown run state"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .running(let endDate):
            var running = container.nestedContainer(keyedBy: RunningKeys.self, forKey: .running)
            try running.encode(endDate, forKey: .endDate)
        case .paused(let remaining):
            var paused = container.nestedContainer(keyedBy: PausedKeys.self, forKey: .paused)
            try paused.encode(remaining, forKey: .remaining)
        }
    }
}

/// Everything the Focus screen needs to know about where we are.
enum SessionStage: Equatable, Sendable {
    case idle
    case active(ActiveSession)
    /// Focus finished and was recorded; waiting for the user to start a break.
    case focusComplete(name: String)
}

extension SessionPhase {
    var label: String {
        switch self {
        case .focus: "Focus"
        case .rest: "Break"
        }
    }
}
