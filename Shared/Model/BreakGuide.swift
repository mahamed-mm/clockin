import Foundation

/// What the dial says during a break spent other than resting, at any
/// moment: the words in place of "Running", the stretch it's on, the
/// dial's value for VoiceOver, which never changes with each breath, and
/// the cues a soft tap marks.
struct BreakGuide: Equatable, Sendable {
    var activity: TickBreak
    var cycle = BreathCycle.standard
    var routine: StretchRoutine

    init(activity: TickBreak, cycle: BreathCycle = .standard) {
        self.activity = activity
        self.cycle = cycle
        routine = StretchRoutine(length: activity.styleLength)
    }

    /// The dial's label at `date`, or nil for the usual one (a rest, paused,
    /// or the stretches done).
    func status(at date: Date) -> String? {
        guard !activity.isPaused else { return nil }
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return nil
        case .breathe: return cycle.phase(at: t).breathingIn ? Copy.breatheIn : Copy.breatheOut
        case .stretch: return move(at: t).map(Copy.stretchName)
        }
    }

    /// Which stretch of how many, while stretching: (2, 4).
    func step(at date: Date) -> (index: Int, count: Int)? {
        guard activity.style == .stretch else { return nil }
        return routine.index(at: activity.styleElapsed(at: date)).map { ($0, routine.count) }
    }

    /// What VoiceOver hears before the time left, or nil for a rest.
    func spoken(at date: Date) -> String? {
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return nil
        case .breathe: return Copy.breatheSpoken(inhale: Int(cycle.inhale), exhale: Int(cycle.exhale))
        case .stretch:
            guard let move = move(at: t), let index = routine.index(at: t) else { return nil }
            return Copy.stretchSpoken(index: index, count: routine.count, move: move)
        }
    }

    /// The moments after `date` the label changes, to the end of the break.
    func changes(after date: Date) -> [Date] {
        guard !activity.isPaused else { return [] }
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return []
        case .breathe:
            return cycle.turns(after: t, through: activity.styleLength).compactMap(activity.date(atStyleElapsed:))
        case .stretch:
            // Each stretch's name shows from the end of the one before.
            return routine.entries.map(\.end).filter { $0 > t }.compactMap(activity.date(atStyleElapsed:))
        }
    }

    /// Which cue the style is on at `date`, counted from when it began: each
    /// breath turning, and each stretch starting and ending. Nil for a rest.
    func cue(at date: Date) -> Int? {
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return nil
        case .breathe: return cycle.phase(at: t).index
        case .stretch: return stretchCues.count(where: { $0 <= t })
        }
    }

    /// How firm the tap for cue `index` is: breathing in firmer than out,
    /// and a stretch starting firmer than one ending, so each is told by feel.
    func strength(ofCue index: Int) -> Double {
        switch activity.style {
        case .rest: 0
        case .breathe: index.isMultiple(of: 2) ? 0.6 : 0.4
        // Cue n is the nth time passed: odd ones start a stretch.
        case .stretch: index.isMultiple(of: 2) ? 0.5 : 0.7
        }
    }

    /// The moments after `date` a cue comes, to the end of the break: the
    /// label's changes, and each stretch starting.
    func cues(after date: Date) -> [Date] {
        guard !activity.isPaused else { return [] }
        let t = activity.styleElapsed(at: date)
        switch activity.style {
        case .rest: return []
        case .breathe: return changes(after: date)
        case .stretch: return stretchCues.filter { $0 > t }.compactMap(activity.date(atStyleElapsed:))
        }
    }

    /// Each stretch's start and end, in the style's time.
    private var stretchCues: [TimeInterval] { routine.entries.flatMap { [$0.start, $0.end] } }

    /// The stretch under way, or coming next while standing between.
    private func move(at t: TimeInterval) -> StretchMove? {
        guard let index = routine.index(at: t) else { return nil }
        return routine.entries[index - 1].move
    }
}
