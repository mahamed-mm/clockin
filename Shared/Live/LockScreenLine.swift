import Foundation

/// What a Lock Screen widget says at one moment: today's focus, or the
/// session running or paused. Pure, so each state can be tested.
enum LockScreenLine: Equatable {
    case today(seconds: TimeInterval, sessions: Int)
    case running(name: String, symbol: String, phase: SessionPhase, end: Date)
    case paused(name: String, symbol: String, phase: SessionPhase)

    /// `symbol` is the running name's; a break shows the cup and its `breakLabel`.
    init(stats: TodayStats, active: ActiveSession?, symbol: String, at date: Date) {
        guard let active, !active.isFinished(at: date) else {
            self = .today(seconds: stats.focusSeconds, sessions: stats.sessionCount)
            return
        }
        let focus = active.phase == .focus
        let name = active.breakLabel ?? Copy.displayName(active.name)
        let shown = focus ? symbol : SessionPhase.rest.symbol
        if let end = active.endDate {
            self = .running(name: name, symbol: shown, phase: active.phase, end: end)
        } else {
            self = .paused(name: name, symbol: shown, phase: active.phase)
        }
    }

    /// Tick in the round widget.
    func pose(hour: Int) -> TickPose {
        switch self {
        case .today: TickPose.forWidget(nil, at: .now, hour: hour)
        case .running(_, _, let phase, _): TickPose.forLive(phase: phase, paused: false, done: false)
        case .paused(_, _, let phase): TickPose.forLive(phase: phase, paused: true, done: false)
        }
    }
}
