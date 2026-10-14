import Foundation

/// What Tick's workout needs from a running focus session: its length and
/// its clock. Everything else is worked out from these at each frame.
struct TickWorkout: Equatable, Sendable {
    enum Style: Sendable {
        /// Boxing and kicking in bursts, tiring as the time runs out.
        case workout
        /// Guard and breathing only, tired near the end; no combos.
        case calm
    }

    /// The session's length, as now planned (Extend adds to it).
    var planned: TimeInterval
    /// When the time runs out, while running.
    var endDate: Date?
    /// The time left, frozen while paused.
    var pausedRemaining: TimeInterval?
    /// The same for a session every time, so its combos are too.
    var seed: UInt64
    var style: Style = .workout

    var isPaused: Bool { endDate == nil }

    /// Like the session's own: never more than the length, never below 0.
    func remaining(at date: Date) -> TimeInterval {
        let left = endDate.map { $0.timeIntervalSince(date) } ?? pausedRemaining ?? planned
        return min(planned, max(0, left))
    }

    func energy(at date: Date) -> WorkoutEnergy {
        WorkoutEnergy.at(planned: planned, remaining: remaining(at: date))
    }

    /// The moment `elapsed` seconds of the session have been done, while running.
    func date(atElapsed elapsed: TimeInterval) -> Date? {
        endDate?.addingTimeInterval(elapsed - planned)
    }

    /// A seed from an id's bytes: the same in every launch, which a
    /// `hashValue` isn't.
    static func seed(from id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        }
    }
}
