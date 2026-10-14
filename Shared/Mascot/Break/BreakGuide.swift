import Foundation

/// What the dial says during a break spent other than resting, at any
/// moment: the words in place of "Running", and the dial's value for
/// VoiceOver, which never changes with each breath.
struct BreakGuide: Equatable, Sendable {
    var activity: TickBreak
    var cycle = BreathCycle.standard

    /// The dial's label at `date`, or nil for the usual one (a rest, or paused).
    func status(at date: Date) -> String? {
        guard !activity.isPaused else { return nil }
        switch activity.style {
        case .rest, .stretch: return nil
        case .breathe:
            return cycle.phase(at: activity.styleElapsed(at: date)).breathingIn ? Copy.breatheIn : Copy.breatheOut
        }
    }

    /// What VoiceOver hears before the time left, or nil for a rest.
    func spoken(at date: Date) -> String? {
        switch activity.style {
        case .rest, .stretch: return nil
        case .breathe: return Copy.breatheSpoken(inhale: Int(cycle.inhale), exhale: Int(cycle.exhale))
        }
    }

    /// The moments after `date` the label changes, to the end of the break.
    func changes(after date: Date) -> [Date] {
        guard !activity.isPaused else { return [] }
        switch activity.style {
        case .rest, .stretch: return []
        case .breathe:
            return cycle.turns(after: activity.styleElapsed(at: date), through: activity.styleLength)
                .compactMap(activity.date(atStyleElapsed:))
        }
    }
}
