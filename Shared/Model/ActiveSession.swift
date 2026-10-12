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

    /// Longest name kept. The name rides along in the Live Activity, whose
    /// whole payload must stay under 4 KB or the request fails.
    static let maxNameLength = 60
    /// Also capped in bytes: a character stacked with combining marks can be
    /// hundreds of bytes on its own.
    static let maxNameBytes = 240

    /// Trimmed and capped; "Focus" when nothing is left.
    static func cleanName(_ raw: String) -> String {
        var capped = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        while capped.utf8.count > maxNameBytes { capped.removeLast() }
        capped = capped.trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? "Focus" : capped
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var endDate: Date? {
        if case .running(let end) = state { return end }
        return nil
    }

    /// Never more than the planned length, so setting the clock back can't
    /// add time to a session.
    func remaining(at now: Date) -> TimeInterval {
        let left = switch state {
        case .running(let end): end.timeIntervalSince(now)
        case .paused(let remaining): remaining
        }
        return min(plannedDuration, max(0, left))
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
    case focusComplete(CompletedFocus)

    var completedFocus: CompletedFocus? {
        if case .focusComplete(let focus) = self { return focus }
        return nil
    }
}

extension SessionPhase {
    var label: String {
        switch self {
        case .focus: Copy.focus
        case .rest: Copy.rest
        }
    }
}
