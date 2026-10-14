import Foundation

extension TickPose {
    /// Night, when an idle Tick sleeps: 22:00 to 06:00.
    static func isNight(hour: Int) -> Bool { hour >= 22 || hour < 6 }

    /// Tick in the app, for where the session stands. `overtime` is the
    /// time kept going past the bell, while it can still be kept.
    static func forStage(_ stage: SessionStage, overtime: TimeInterval?, hour: Int) -> TickPose {
        switch stage {
        case .idle:
            return isNight(hour: hour) ? .sleeping : .ready
        case .active(let session):
            return forLive(phase: session.phase, paused: session.isPaused, done: false)
        case .focusComplete(let focus):
            if focus.outcome == .endedEarly { return .interrupted }
            // A minute past the bell and still going: back to work.
            if let overtime, overtime >= 60 { return .working }
            // The fourth full session of the set: proud, not a streak.
            return focus.isLongBreak == true ? .streak : .done
        }
    }

    /// Tick on the Lock Screen and in the Dynamic Island.
    static func forLive(phase: SessionPhase, paused: Bool, done: Bool) -> TickPose {
        if done { return phase == .focus ? .done : .ready }
        if paused { return .waiting }
        return phase == .focus ? .working : .onBreak
    }

    /// Tick on the Home Screen widget: the running session, or ready.
    static func forWidget(_ session: ActiveSession?, at now: Date, hour: Int) -> TickPose {
        guard let session else { return isNight(hour: hour) ? .sleeping : .ready }
        return forLive(phase: session.phase, paused: session.isPaused, done: session.isFinished(at: now))
    }
}
