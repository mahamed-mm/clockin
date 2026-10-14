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
        /// Length of the break that follows a focus phase, for the "done" copy.
        /// Comes from the app, which knows the real setting. Optional for older activities.
        var breakDuration: TimeInterval?
        /// The session name's symbol. In the state rather than the attributes
        /// so a new pick shows at once. Optional for older activities.
        var symbol: String?

        var isPaused: Bool { pausedRemaining != nil }

        /// Beside the name: the session's symbol, or the cup on a break.
        var nameSymbol: String {
            phase == .focus ? (symbol ?? SymbolCatalog.unnamed) : SessionPhase.rest.symbol
        }

        /// Interval used by timer text and progress views.
        var timerRange: ClosedRange<Date> {
            let end = endDate ?? .now
            return end.addingTimeInterval(-plannedDuration)...end
        }

        init(session: ActiveSession, completedToday: Int? = nil, breakDuration: TimeInterval? = nil,
             symbol: String? = nil) {
            phase = session.phase
            plannedDuration = session.plannedDuration
            self.completedToday = completedToday
            self.breakDuration = breakDuration
            self.symbol = symbol
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
    /// The session this card belongs to, so updates and the pause button can
    /// tell it from a card left by an earlier session. Optional so activities
    /// started by older builds still decode.
    var sessionID: UUID?
}
