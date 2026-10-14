import Foundation

/// The workout as a function of the timer's dates: which combo and move
/// is under way, on the stance for how tired Tick is, how it breathes and
/// bounces, and when anything next moves. Nothing is counted, so a session
/// opened mid-way, or come back to from the background, shows exactly
/// where it is.
struct WorkoutLoops: Sendable {
    var workout: TickWorkout
    var scheduler: ComboScheduler
    var sweat: SweatEmitter

    init(workout: TickWorkout, scheduler: ComboScheduler? = nil, sweat: SweatEmitter? = nil) {
        self.workout = workout
        let scheduler = scheduler ?? ComboScheduler(planned: workout.planned, seed: workout.seed)
        self.scheduler = scheduler
        self.sweat = sweat ?? SweatEmitter(planned: workout.planned, seed: workout.seed, scheduler: scheduler)
    }

    private var phases: WorkoutEnergy.Plan { WorkoutEnergy.Plan(planned: workout.planned) }

    /// Tick at `date`: mid-move during a combo, in guard between (settling
    /// with a few bounces after each combo), breathing hard once tired.
    func frame(at date: Date) -> WorkoutFrame {
        let energy = workout.energy(at: date)
        var params = WorkoutParams(energy)
        let elapsed = energy.elapsed
        var frame: WorkoutFrame
        if let move = move(at: date) {
            // A combo reaches as far as it did when it began.
            params.reach = move.reach
            frame = WorkoutFrame(params: params, move: move.move, at: move.t)
        } else {
            frame = WorkoutFrame(params: params)
            let lift = bounce(at: elapsed, params: params)
            if lift != 0 { frame.rig = frame.rig.applying(WorkoutPose(lift: lift)) }
        }
        if params.breathPeriod != nil {
            let (breath, exhaling) = breath(at: elapsed)
            frame.motion.breath = breath
            frame.motion.breathDepth = params.breathDepth
            if frame.face.mouth == .pant { frame.face.mouthOpen = 0.35 + 0.65 * breath }
            // Worn out, each breath out puffs.
            if params.face == .panting, let exhaling { frame.motion.puff = exhaling }
        }
        frame.rig = blended(frame.rig, at: elapsed)
        frame.motion.blink = faceBlink(at: elapsed)
        frame.motion.sweat = sweat.drops(at: elapsed)
        return frame
    }

    /// Where the stance changes (down onto the knees, back up for the final
    /// push), it eases over half a second from the old stance to the new.
    private func blended(_ rig: TickRig, at elapsed: TimeInterval) -> TickRig {
        guard let change = stanceChanges.last(where: { elapsed >= $0 && elapsed < $0 + Self.stanceBlend }) else { return rig }
        let before = TickRig(workout: WorkoutParams(.at(planned: workout.planned, remaining: workout.planned - change + 0.001)))
        let x = (elapsed - change) / Self.stanceBlend
        let eased = x * x * (3 - 2 * x)
        var blended = before
        blended.animatableData = before.animatableData + (rig.animatableData - before.animatableData).scaled(by: eased)
        return blended
    }

    static let stanceBlend = 0.5

    /// When Tick goes down onto its knees, and gets back up.
    private var stanceChanges: [TimeInterval] {
        let plan = phases
        return [plan.exhausted, plan.finalPush].filter { $0 > 0 && $0 < plan.planned }
    }

    /// The move under way, if the timer is running.
    func move(at date: Date) -> (move: WorkoutMove, t: TimeInterval, reach: Double)? {
        guard !workout.isPaused else { return nil }
        return scheduler.move(at: workout.energy(at: date).elapsed)
    }

    // MARK: Breathing, bouncing, blinking

    /// Between combos in a round Tick bounces on its toes, dying away over
    /// 1.2 s, as high as its energy allows (lift is downward, so a bounce is
    /// negative). After a round it stands still.
    func bounce(at elapsed: TimeInterval, params: WorkoutParams) -> Double {
        guard let since = bouncing(at: elapsed), params.bounce > 0 else { return 0 }
        return -1.6 * params.bounce * abs(sin(.pi * since / 0.4)) * (1 - since / Self.bounceLength)
    }

    static let bounceLength = 1.2
    /// A rest this short or shorter is inside a round.
    static let roundGap = 3.0

    /// Seconds into the bounce after a combo, while it lasts.
    private func bouncing(at elapsed: TimeInterval) -> TimeInterval? {
        guard let end = scheduler.lastEnd(by: elapsed), elapsed - end < Self.bounceLength,
              let next = scheduler.nextStart(after: end), next - end <= Self.roundGap else { return nil }
        return elapsed - end
    }

    /// 0...1...0 through each heavy breath, and 0...1 through the breath
    /// out (nil breathing in). The breaths quicken through the tired
    /// stretch (2.2 s to 1.5 s) and stay quick when worn out; the phase is
    /// added up as they quicken, so they never jump or race.
    func breath(at elapsed: TimeInterval) -> (Double, exhaling: Double?) {
        let cycles = breathCycles(at: elapsed)
        let f = cycles - cycles.rounded(.down)
        return (0.5 - 0.5 * cos(2 * .pi * f), f >= 0.5 ? (f - 0.5) * 2 : nil)
    }

    /// Breaths taken since the tired stretch began.
    private func breathCycles(at elapsed: TimeInterval) -> Double {
        let plan = phases
        let tired = plan.span(of: .tired)
        let t = min(max(0, elapsed - tired.lowerBound), tired.upperBound - tired.lowerBound)
        var cycles = 0.0
        if !tired.isEmpty {
            // The period goes from a to a + b·span linearly; ∫ dt / (a + b t) = ln(1 + b t / a) / b.
            let a = 2.2, b = (1.5 - 2.2) / (tired.upperBound - tired.lowerBound)
            cycles = log(1 + b * t / a) / b
        }
        if elapsed > plan.exhausted { cycles += (elapsed - max(plan.exhausted, tired.upperBound)) / 1.2 }
        return cycles
    }

    /// When the face changes on its own: half-way through tired (strained),
    /// worn out (panting), and the final push (strained again).
    var faceChanges: [TimeInterval] {
        let plan = phases
        let changes = [plan.tired + (plan.exhausted - plan.tired) / 2, plan.exhausted, plan.finalPush]
        return changes.filter { $0 > 0 && $0 < plan.planned }
    }

    /// A blink shut at each face change, so the new face appears behind it.
    func faceBlink(at elapsed: TimeInterval) -> Double {
        faceChanges.map { max(0, 1 - abs(elapsed - $0) / 0.09) }.max() ?? 0
    }

    // MARK: Frames

    /// `date` itself while something moves (a combo, a bounce, a blink,
    /// hard breathing), otherwise when it next will (never while paused).
    func nextMovement(from date: Date) -> Date {
        guard !workout.isPaused else { return .distantFuture }
        let elapsed = workout.energy(at: date).elapsed
        if moving(at: elapsed) { return date }
        let starts = [scheduler.nextStart(after: elapsed), faceChanges.map { $0 - 0.09 }.first { $0 > elapsed },
                      phases.tired > elapsed ? phases.tired : nil]
        return starts.compactMap { $0 }.min().flatMap { workout.date(atElapsed: $0) } ?? .distantFuture
    }

    /// Seconds between frames: 30 a second for combos, bounces and blinks,
    /// 15 when only breathing.
    func frameInterval(at date: Date) -> TimeInterval {
        let elapsed = workout.energy(at: date).elapsed
        let quick = scheduler.entry(at: elapsed) != nil || bouncing(at: elapsed) != nil || faceBlink(at: elapsed) > 0
            || stanceChanges.contains { elapsed >= $0 && elapsed < $0 + Self.stanceBlend }
        return quick ? 1.0 / 30 : 1.0 / 15
    }

    private func moving(at elapsed: TimeInterval) -> Bool {
        if scheduler.entry(at: elapsed) != nil || faceBlink(at: elapsed) > 0 { return true }
        if bouncing(at: elapsed) != nil { return true }
        return elapsed >= phases.tired
    }
}
