import Foundation

enum SessionPhase: String, Codable, Hashable, Sendable {
    case focus
    case rest
}

/// The single in-progress session. Persisted so the timer survives relaunch.
struct ActiveSession: Codable, Equatable, Sendable {
    enum RunState: Codable, Equatable, Sendable {
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
