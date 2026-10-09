import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: SessionPhase
        /// Set while running.
        var endDate: Date?
        /// Set while paused.
        var pausedRemaining: TimeInterval?
        var plannedDuration: TimeInterval
        /// Focus sessions finished today, for the session pills. Optional so
        /// activities started by older builds still decode.
        var completedToday: Int?

        var isPaused: Bool { pausedRemaining != nil }

        /// Interval used by timer text and progress views.
        var timerRange: ClosedRange<Date> {
            let end = endDate ?? .now
            return end.addingTimeInterval(-plannedDuration)...end
        }

        init(session: ActiveSession, completedToday: Int? = nil) {
            phase = session.phase
            plannedDuration = session.plannedDuration
            self.completedToday = completedToday
            switch session.state {
            case .running(let end):
                endDate = end
                pausedRemaining = nil
            case .paused(let remaining):
                endDate = nil
                pausedRemaining = remaining
            }
        }
    }

    var sessionName: String
}
