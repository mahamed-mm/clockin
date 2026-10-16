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
        /// "+5 min" can be added now: set by the app in the last five minutes
        /// of focus, while it runs. Optional for older activities.
        var canExtend: Bool?
        /// The break is the long one after a set, so a new set comes next.
        /// Optional for older activities.
        var isLongBreak: Bool?
        /// Break only: how it's spent, sent again when a chip changes it.
        /// Optional for older activities, which rest.
        var breakStyle: BreakStyle?
        /// Break only: the next planned session, for Start focus and the
        /// line under the name once it's over. Nil without a plan, and in
        /// older activities, which start the same name again.
        var next: NextUp?

        var isPaused: Bool { pausedRemaining != nil }

        /// "Focus", "Break", "Long break" or "Break · Stretch": the same words
        /// as `ActiveSession.breakLabel`.
        var phaseLabel: String {
            phase == .focus ? Copy.focus : Copy.breakLabel(style: breakStyle, isLong: isLongBreak == true)
        }

        /// Beside the name: the session's symbol, or the cup on a break.
        var nameSymbol: String {
            phase == .focus ? (symbol ?? SymbolCatalog.unnamed) : SessionPhase.rest.symbol
        }

        /// The label once it ran out: "Focus complete" or "Break's over".
        var doneStatus: String { phase == .focus ? Copy.focusComplete : Copy.breakOver }

        /// The line under the name once it ran out: the break it earned, or
        /// which session of the set comes next.
        var doneLine: String {
            switch phase {
            case .focus: Copy.breakLine(seconds: breakDuration ?? Preset.classic.shortBreak)
            case .rest:
                if let next {
                    BreakOverMoment.nextLine(name: next.name, fullToday: completedToday ?? 0, afterLong: isLongBreak == true)
                } else {
                    BreakOverMoment.nextCardLine(fullToday: completedToday ?? 0, afterLong: isLongBreak == true)
                }
            }
        }

        /// Interval used by timer text and progress views.
        var timerRange: ClosedRange<Date> {
            let end = endDate ?? .now
            return end.addingTimeInterval(-plannedDuration)...end
        }

        init(session: ActiveSession, completedToday: Int? = nil, breakDuration: TimeInterval? = nil,
             symbol: String? = nil, canExtend: Bool? = nil, next: NextUp? = nil) {
            phase = session.phase
            plannedDuration = session.plannedDuration
            self.completedToday = completedToday
            self.breakDuration = breakDuration
            self.symbol = symbol
            self.canExtend = canExtend
            isLongBreak = session.isLongBreak
            breakStyle = session.phase == .rest ? session.breakStyle : nil
            self.next = session.phase == .rest ? next : nil
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
