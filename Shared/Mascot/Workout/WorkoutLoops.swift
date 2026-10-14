import Foundation

/// The workout as a function of the timer's dates: which combo and move
/// is under way, on the stance for how tired Tick is, and when anything
/// next moves. Nothing is counted, so a session opened mid-way, or come
/// back to from the background, shows exactly where it is.
struct WorkoutLoops: Sendable {
    var workout: TickWorkout
    var scheduler: ComboScheduler

    init(workout: TickWorkout, scheduler: ComboScheduler? = nil) {
        self.workout = workout
        self.scheduler = scheduler ?? ComboScheduler(planned: workout.planned, seed: workout.seed)
    }

    /// Tick at `date`: mid-move during a combo, in guard between.
    func frame(at date: Date) -> WorkoutFrame {
        var params = WorkoutParams(workout.energy(at: date))
        guard let move = move(at: date) else { return WorkoutFrame(params: params) }
        // A combo reaches as far as it did when it began.
        params.reach = move.reach
        return WorkoutFrame(params: params, move: move.move, at: move.t)
    }

    /// The move under way, if the timer is running.
    func move(at date: Date) -> (move: WorkoutMove, t: TimeInterval, reach: Double)? {
        guard !workout.isPaused else { return nil }
        return scheduler.move(at: workout.energy(at: date).elapsed)
    }

    /// `date` itself while a combo is under way, otherwise when the next
    /// one starts (never while paused).
    func nextMovement(from date: Date) -> Date {
        guard !workout.isPaused else { return .distantFuture }
        let elapsed = workout.energy(at: date).elapsed
        if scheduler.entry(at: elapsed) != nil { return date }
        return scheduler.nextStart(after: elapsed).flatMap { workout.date(atElapsed: $0) } ?? .distantFuture
    }

    /// Combos are drawn at 30 frames a second.
    static let frameInterval = 1.0 / 30
}
