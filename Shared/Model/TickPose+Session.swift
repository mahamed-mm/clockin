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

/// Which state Tick shows in the app, and when that will change on its
/// own: the one place the rules live.
///
/// - The ringing alarm beats everything. After a focus session it rings,
///   then Tick is done; after a break it rings, then Tick is ready.
/// - A set of four shows done first, then the proud streak a few seconds
///   later; it's dropped as soon as the stage moves on.
/// - Hello, once: on first launch or back after a week away, then ready.
/// - Idle at night, or idle for ten minutes, Tick falls asleep.
struct TickDirector: Equatable {
    var stage: SessionStage
    var alarmRinging = false
    /// Time kept going past the bell (see `SessionEngine.overtime`).
    var overtime: TimeInterval? = nil
    var hour: Int
    /// When the stage began, as Tick saw it.
    var stageSince: Date
    /// Until when Tick says hello, if it greets this time.
    var helloUntil: Date? = nil

    /// How long done shows before a set of four's streak.
    static let streakDelay: TimeInterval = 3
    /// Idle this long, and Tick falls asleep.
    static let dozeAfter: TimeInterval = 10 * 60
    /// Away this long, and Tick says hello again.
    static let greetAfter: TimeInterval = 7 * 24 * 3600
    /// How long a hello lasts: the pop and three waves.
    static let helloLength: TimeInterval = 2.5
    /// Changes closer together than this show only the last.
    static let settle: TimeInterval = 0.3

    func pose(at now: Date) -> TickPose {
        if alarmRinging { return .ringing }
        switch stage {
        case .idle:
            if let helloUntil, now < helloUntil { return .hello }
            if TickPose.isNight(hour: hour) || now.timeIntervalSince(stageSince) >= Self.dozeAfter { return .sleeping }
            return .ready
        case .active(let session):
            return TickPose.forLive(phase: session.phase, paused: session.isPaused, done: false)
        case .focusComplete:
            let pose = TickPose.forStage(stage, overtime: overtime, hour: hour)
            if pose == .streak, now.timeIntervalSince(stageSince) < Self.streakDelay { return .done }
            return pose
        }
    }

    /// The next moment the pose changes without anything happening: the
    /// streak after done, the end of hello, dozing off.
    func nextChange(after now: Date) -> Date? {
        guard !alarmRinging else { return nil }
        var dates: [Date] = []
        switch stage {
        case .idle:
            if let helloUntil, helloUntil > now { dates.append(helloUntil) }
            dates.append(stageSince.addingTimeInterval(Self.dozeAfter))
        case .focusComplete(let focus) where focus.isLongBreak == true && focus.outcome != .endedEarly:
            dates.append(stageSince.addingTimeInterval(Self.streakDelay))
        default:
            break
        }
        return dates.filter { $0 > now }.min()
    }

    /// Whether Tick greets: on first launch, or back after a week away.
    static func greets(lastSeen: Date?, now: Date) -> Bool {
        guard let lastSeen else { return true }
        return now.timeIntervalSince(lastSeen) >= greetAfter
    }

    /// When a change at `now` may show: at once, unless the last one
    /// showed under 0.3 s ago, then when that time is up (only the latest
    /// change by then is shown).
    static func showTime(for now: Date, lastShown: Date?) -> Date {
        guard let lastShown, now.timeIntervalSince(lastShown) < settle else { return now }
        return lastShown.addingTimeInterval(settle)
    }
}

extension TickPose {
    /// Tick's ring for where things stand: time left while focusing (and
    /// frozen when paused), filling up through a break, full when idle,
    /// and what was left when a session was stopped early. Done and
    /// ringing colour the whole ring.
    static func ringProgress(for stage: SessionStage, at now: Date) -> Double {
        switch stage {
        case .idle:
            return 1
        case .active(let session):
            guard session.plannedDuration > 0 else { return 1 }
            let left = session.remaining(at: now) / session.plannedDuration
            return session.phase == .focus ? left : 1 - left
        case .focusComplete(let focus):
            guard focus.outcome == .endedEarly, let planned = focus.plannedSeconds, planned > 0 else { return 0 }
            return min(1, max(0, 1 - focus.focusSeconds / planned))
        }
    }
}

extension TickWorkout {
    /// The workout for a running or paused session.
    init(session: ActiveSession, style: Style = .workout) {
        self.init(planned: session.plannedDuration, endDate: session.endDate,
                  pausedRemaining: session.isPaused ? session.remaining(at: .now) : nil,
                  seed: Self.seed(from: session.id), style: style)
    }
}
