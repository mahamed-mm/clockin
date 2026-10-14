import Foundation

/// A break spent stretching or breathing, as a function of the break's own
/// time: the mug put away and Tick up on its feet, each stretch at its
/// moment, then back down with the mug once the routine is done. Breathing
/// is a still stance; its breath comes from `BreathCycle`. Nothing is
/// counted, so a break opened mid-way shows exactly where it is.
struct BreakLoops: Equatable, Sendable {
    var activity: TickBreak
    var routine: StretchRoutine

    init(activity: TickBreak) {
        self.activity = activity
        routine = StretchRoutine(length: activity.styleLength)
    }

    /// Easing from the break's pose to standing, and back.
    static let blend = 0.6

    /// When Tick is back with the mug, in the style's time.
    var rejoinsRest: TimeInterval? {
        activity.style == .stretch ? routine.end + Self.blend : nil
    }

    /// Whether Tick is leading the break at `date`, rather than resting:
    /// breathing throughout, stretching until the routine is done.
    func leads(at date: Date) -> Bool {
        switch activity.style {
        case .rest: false
        case .breathe: true
        case .stretch: activity.styleElapsed(at: date) < routine.end + Self.blend
        }
    }

    /// Tick at `date`, or nil when it's simply resting with the mug.
    func frame(at date: Date) -> WorkoutFrame? {
        guard leads(at: date) else { return nil }
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return nil
        case .breathe:
            return WorkoutFrame(rig: Self.mixed(TickRig(.onBreak), .breathing, t / Self.blend), face: .breathing)
        case .stretch:
            if t >= routine.end {
                // Done: back down, the mug coming back into the hand.
                return WorkoutFrame(rig: Self.mixed(.standing, TickRig(.onBreak), (t - routine.end) / Self.blend),
                                    face: .stretching)
            }
            let pose = routine.entry(at: t).map { $0.move.pose(at: t - $0.start) } ?? .rest
            let rig = Self.mixed(TickRig(.onBreak), TickRig.standing.applying(pose), t / Self.blend)
            return WorkoutFrame(rig: rig, face: TickFace.stretching.applying(pose))
        }
    }

    /// Held for Reduce Motion and Low Power Mode: each stretch at its fullest
    /// while it's under way, standing between, and the mug once done.
    func stillFrame(at date: Date) -> WorkoutFrame? {
        guard leads(at: date) else { return nil }
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return nil
        case .breathe: return WorkoutFrame(rig: .breathing, face: .breathing)
        case .stretch:
            guard t < routine.end else { return nil }
            let pose = routine.entry(at: t)?.move.stillPose ?? .rest
            return WorkoutFrame(rig: TickRig.standing.applying(pose), face: TickFace.stretching.applying(pose))
        }
    }

    /// Which still shows at `date`, so stills cross-fade as they change.
    func stillKey(at date: Date) -> String {
        guard leads(at: date) else { return "rest" }
        return routine.entry(at: activity.styleElapsed(at: date))?.move.rawValue ?? activity.style.rawValue
    }

    /// The moments the stills change: each stretch starting and ending, and the routine done.
    func stillChanges(after date: Date) -> [Date] {
        guard activity.style == .stretch else { return [] }
        let t = activity.styleElapsed(at: date)
        return routine.entries.flatMap { [$0.start, $0.end] }.filter { $0 > t }.compactMap(activity.date(atStyleElapsed:))
    }

    // MARK: Frames

    /// `date` itself while something moves (easing up or down, a stretch
    /// on the move), otherwise when it next will; never while paused,
    /// breathing (the breath is moved for it) or resting.
    func nextMovement(from date: Date) -> Date {
        guard !activity.isPaused, leads(at: date) else { return .distantFuture }
        let t = activity.styleElapsed(at: date)
        if moving(at: t) { return date }
        let next: TimeInterval? = switch activity.style {
        case .rest, .breathe: nil
        case .stretch: nextMoving(after: t)
        }
        return next.flatMap(activity.date(atStyleElapsed:)) ?? .distantFuture
    }

    /// 30 frames a second while moving.
    func frameInterval(at date: Date) -> TimeInterval { 1.0 / 30 }

    private func moving(at t: TimeInterval) -> Bool {
        if t < Self.blend { return true }
        guard activity.style == .stretch else { return false }
        if t >= routine.end { return t < routine.end + Self.blend }
        guard let entry = routine.entry(at: t) else { return false }
        let into = t - entry.start
        return !entry.move.stillSpans.contains { $0.contains(into) }
    }

    /// The next moment from `t` a stretch moves, or the routine ends.
    private func nextMoving(after t: TimeInterval) -> TimeInterval? {
        if let entry = routine.entry(at: t) {
            let into = t - entry.start
            if let span = entry.move.stillSpans.first(where: { $0.contains(into) }) {
                return entry.start + span.upperBound
            }
            return t
        }
        if let next = routine.entries.first(where: { $0.start > t }) { return next.start }
        return t < routine.end + Self.blend ? max(t, routine.end) : nil
    }

    /// `a` eased toward `b` by `x` (0...1).
    static func mixed(_ a: TickRig, _ b: TickRig, _ x: Double) -> TickRig {
        let x = min(1, max(0, x))
        guard x < 1 else { return b }
        let eased = x * x * (3 - 2 * x)
        var rig = a
        rig.animatableData = a.animatableData + (b.animatableData - a.animatableData).scaled(by: eased)
        return rig
    }
}
