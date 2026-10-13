import SwiftUI

/// When a timer view needs to redraw: every second while a countdown runs,
/// on whole seconds before its end so the digits change together with the
/// Lock Screen's, and otherwise only at the given moments. A paused or idle
/// screen doesn't redraw at all.
struct TickSchedule: TimelineSchedule, Hashable {
    /// The end of a running countdown, or nil when nothing counts down.
    var countdownEnd: Date?
    /// Seconds between ticks; at least a minute when the system asks for
    /// low-frequency updates (e.g. Always On).
    var interval: TimeInterval = 1
    /// Moments to redraw even without a countdown, e.g. when a control unlocks.
    var wakeDates: [Date] = []

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        let step = mode == .lowFrequency ? max(interval, 60) : interval
        return Entries(upcoming: startDate, end: countdownEnd, step: max(step, 0.1),
                       wakes: wakeDates.filter { $0 > startDate }.sorted())
    }

    struct Entries: Sequence, IteratorProtocol {
        fileprivate var upcoming: Date?
        fileprivate let end: Date?
        fileprivate let step: TimeInterval
        fileprivate var wakes: [Date]

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            let tick = end.flatMap { Self.tick(after: current, end: $0, step: step) }
            while let wake = wakes.first, wake <= current { wakes.removeFirst() }
            upcoming = [tick, wakes.first].compactMap(\.self).min()
            return current
        }

        /// The first moment after `date` that is a whole number of steps before `end`.
        static func tick(after date: Date, end: Date, step: TimeInterval) -> Date? {
            guard date < end else { return nil }
            let steps = (end.timeIntervalSince(date) / step).rounded(.down)
            var tick = end.addingTimeInterval(-steps * step)
            if tick <= date { tick = tick.addingTimeInterval(step) }
            return tick <= end ? tick : nil
        }
    }
}
