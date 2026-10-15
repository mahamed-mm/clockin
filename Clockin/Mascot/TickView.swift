import SwiftUI

private extension TickMotion {
    /// What the parts draw: the motion without what moves the whole figure.
    var drawn: TickMotion {
        var motion = self
        motion.breath = 0
        motion.lean = 0
        motion.tremble = 0
        motion.blink = 0
        motion.shrink = 0
        motion.squash = 0
        return motion
    }
}

/// Frames for Tick's loops: 30 a second while something moves (and
/// through the face-swap blink after a change), then none until the next
/// blink, tap or hop.
struct TickLoopSchedule: TimelineSchedule {
    let loops: TickLoops
    let since: Date
    let pokedAt: Date?
    /// A parked thought is on its way: frames through its flight and catch.
    var caughtAt: Date? = nil
    let paused: Bool
    /// The debug menu's slow motion.
    let speed: Double
    /// A workout under way: combos move to the session's own clock.
    var workout: WorkoutLoops? = nil
    /// A break spent stretching: each stretch moves to the break's own clock.
    var breakLoops: BreakLoops? = nil

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator {
            guard let date = next else { return nil }
            guard !paused, mode != .lowFrequency else {
                next = nil
                return date
            }
            let elapsed = date.timeIntervalSince(since) / speed
            let frame = elapsed + loops.frameInterval(at: elapsed)
            // The face swaps behind a blink in the first 0.18 s; a poke lasts 0.6 s.
            let poking = pokedAt.map { date.timeIntervalSince($0) / speed < TickTouch.pokeLength } ?? false
            let catching = caughtAt.map {
                let t = date.timeIntervalSince($0)
                return t >= 0 && t < TickCatch.length
            } ?? false
            let soonest = frame < 0.2 || poking || catching ? frame : loops.nextMovement(from: frame)
            var upcoming = since.addingTimeInterval(soonest * speed)
            // Wake for a catch still to come.
            if let caughtAt, caughtAt > date { upcoming = min(upcoming, caughtAt) }
            if let workout {
                // The next combo frame, or the next combo's start.
                let step = date.addingTimeInterval(workout.frameInterval(at: date, pose: loops.pose))
                upcoming = min(upcoming, max(step, workout.nextMovement(from: step, pose: loops.pose, since: since)))
            }
            if let breakLoops {
                let step = date.addingTimeInterval(breakLoops.frameInterval(at: date))
                upcoming = min(upcoming, max(step, breakLoops.nextMovement(from: step)))
            }
            next = upcoming
            return date
        }
    }
}

/// Where Tick's ring gets its time left.
enum TickProgress: Equatable {
    /// The character sheet's own, for the state.
    case sheet
    case fixed(Double)
}

/// Tick in the app, alive: a change of state springs every part of the
/// body to the new pose, the face changes behind a blink, and each state
/// has its idle loop. The loops stop when Tick is off screen, the app is
/// in the background, the phone is saving power, or Reduce Motion is on
/// (then states cross-fade). Its crown works the timer, a tap on its body
/// makes it giggle, and while ringing any tap stops the alarm.
struct TickView: View {
    let pose: TickPose
    var progress: TickProgress = .sheet
    /// Increments when a focus session completes, for the "ding" hop.
    var celebration = 0
    /// What the crown does (start, pause, resume), and its name for
    /// VoiceOver. Without it the crown is just part of Tick.
    var crown: (label: String, action: () -> Void)? = nil
    /// Stops the alarm, while ringing.
    var onDismiss: (() -> Void)? = nil
    /// The focus session as a workout: while working, Tick boxes and
    /// kicks in bursts, tiring as the time runs out.
    var workout: TickWorkout? = nil
    /// The break as it's being spent: stretching or breathing, Tick puts
    /// the mug away and leads it.
    var breakActivity: TickBreak? = nil
    /// Just back from a break: ready comes in with a stretch and a yawn.
    var backToWork = false
    /// When a parked thought reaches Tick: it catches it, or nods mid-combo.
    var caughtAt: Date? = nil
    /// False takes the headphones off: nothing is playing, and the workout
    /// (which always wears them) isn't on. Nil leaves them to the pose.
    var listening: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.tickReduceMotion) private var galleryReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppServices.self) private var services

    /// When the current state began, for its loop.
    @State private var since = Date.now
    /// The state whose face shows until the blink has shut.
    @State private var facePose: TickPose?
    @State private var faceSwap: Date?
    @State private var onScreen = false
    /// Whether the current state's entry plays: only for a change seen
    /// happen, not on showing or coming back from the background.
    @State private var entering = false
    @State private var activeSince = Date.now
    /// The crown held down.
    @State private var pressing = false
    @State private var crownTaps = 0
    @State private var pokedAt: Date?
    @State private var pokes = 0
    @State private var seed = Double.random(in: 0..<100)
    @State private var combos = ComboCache()
    /// A workout just started, seen happen: Tick gloves up first.
    @State private var gearingUp = false
    /// Moved on when a break's stretches are done, so Tick goes back to resting.
    @State private var breakRefresh = 0

    private var reduceMotion: Bool { systemReduceMotion || galleryReduceMotion }
    private var still: Bool { reduceMotion || services.power.isConstrained }
    private var paused: Bool { !onScreen || scenePhase != .active }
    private var loops: TickLoops {
        // Working out, or paused worn out, Tick breathes hard instead of in calm spells.
        let breathesHard = workoutLoops.map { !$0.isCalm && (pose == .working || (pose == .waiting && $0.pausedMoving)) } ?? false
        return TickLoops(pose: pose, seed: seed, entering: entering, breathes: !breathesHard && !breathing,
                         gearsUp: gearingUp, mug: activeBreak == nil, backToWork: backToWork && pose == .ready)
    }

    /// The break, while Tick is leading it rather than resting with the mug.
    private var activeBreak: TickBreak? {
        _ = breakRefresh
        guard pose == .onBreak, let breakActivity, BreakLoops(activity: breakActivity).leads(at: .now) else { return nil }
        return breakActivity
    }

    /// Breathing along with the halo: Tick's breath follows the same cycle.
    private var breathing: Bool { activeBreak?.style == .breathe }

    private var breakLoops: BreakLoops? { activeBreak.map(BreakLoops.init(activity:)) }

    /// When the stretches are done and Tick has the mug again: then it rests as usual.
    private var rejoinsRest: Date? {
        guard let activeBreak, let t = BreakLoops(activity: activeBreak).rejoinsRest else { return nil }
        return activeBreak.date(atStyleElapsed: t)
    }

    /// Back from a break, seen happen: up on its feet, a reach and a yawn,
    /// easing into ready over the last half second.
    private func stretchingIn(elapsed: TimeInterval) -> WorkoutFrame? {
        let move = StretchMove.backToWork
        guard pose == .ready, backToWork, entering, elapsed < move.duration else { return nil }
        let stretch = move.pose(at: elapsed)
        let rig = BreakLoops.mixed(TickRig.standing.applying(stretch), TickRig(.ready),
                                   (elapsed - (move.duration - 0.5)) / 0.5)
        return WorkoutFrame(rig: rig, face: TickFace(.ready).applying(stretch))
    }

    /// The workout behind Tick: working through one, paused in one, or just done.
    private var workoutLoops: WorkoutLoops? {
        guard let workout, Self.workoutPoses.contains(pose) else { return nil }
        let (scheduler, sweat) = combos.parts(for: workout)
        return WorkoutLoops(workout: workout, scheduler: scheduler, sweat: sweat)
    }

    private static let workoutPoses: Set<TickPose> = [.working, .waiting, .done, .ringing, .streak]

    /// When a still Tick changes: a poke and its end, and each face change of a workout.
    private var stillDates: [Date] {
        var dates = pokedAt.map { [$0, $0.addingTimeInterval(TickTouch.pokeLength)] } ?? []
        if pose == .working, let loops = workoutLoops {
            dates += loops.faceChanges.compactMap { loops.workout.date(atElapsed: $0) }.filter { $0 > .now }
        }
        if let breakLoops { dates += breakLoops.stillChanges(after: .now) }
        return dates.sorted()
    }

    /// Tick at `date`, `elapsed` into the state, when a workout is behind it.
    private func workoutFrame(_ loops: WorkoutLoops?, at date: Date, elapsed: TimeInterval) -> WorkoutFrame? {
        guard let loops else { return nil }
        switch pose {
        case .working:
            let frame = loops.frame(at: date)
            return gearingUp && elapsed < WorkoutLoops.gearUpLength ? loops.gearingUp(frame, at: elapsed) : frame
        case .waiting:
            return loops.pausedFrame(at: date)
        case .done:
            return loops.championFrame(sinceDone: elapsed)
        default:
            // Ringing, or a set of four: the gloves stay on.
            var rig = TickRig(pose)
            rig.gloves = 1
            return WorkoutFrame(rig: rig, face: TickFace(pose))
        }
    }

    var body: some View {
        Group {
            if still {
                // Cross-fades between stills; a poke still changes the face. A
                // workout is calm here, and changes face as Tick tires.
                // Now first: an explicit timeline draws its first date first, even a later one.
                TimelineView(.explicit([.now] + stillDates.filter { $0 > .now })) { context in
                    let calm = workoutLoops.map { CalmLoops($0) }
                    let frame = pose == .working
                        ? calm?.loops.calmFrame(at: context.date)
                        : workoutFrame(calm?.loops, at: context.date, elapsed: .infinity)
                            ?? breakLoops?.stillFrame(at: context.date)
                    let key = (frame.map { "\($0.face.eyes)\($0.face.mouth)" } ?? "")
                        + (breakLoops?.stillKey(at: context.date) ?? "")
                    figure(motion: .still, face: face(at: context.date, base: frame?.face).0, rig: frame?.rig)
                        .id(key)
                        .transition(.opacity)
                        .animation(Motion.calm(true), value: key)
                }
                .id(pose)
                .transition(.opacity)
            } else {
                // Frames only while something moves (30 a second), none between.
                let workoutLoops = workoutLoops
                TimelineView(TickLoopSchedule(loops: loops, since: since, pokedAt: pokedAt, caughtAt: caughtAt,
                                              paused: paused, speed: Motion.speed, workout: workoutLoops,
                                              breakLoops: breakLoops)) { context in
                    let elapsed = context.date.timeIntervalSince(since) / Motion.speed
                    let frame = workoutFrame(workoutLoops, at: context.date, elapsed: elapsed)
                        ?? breakLoops?.frame(at: context.date) ?? stretchingIn(elapsed: elapsed)
                    let motion = paused ? TickMotion.still
                        : withCatch(withPoke(withWorkout(loops.motion(at: elapsed), frame), at: context.date),
                                    at: context.date, workout: workoutLoops)
                    let (face, swapBlink) = face(at: context.date, base: frame?.face)
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height)
                        // Drawn once into a layer, so moving it costs no redraw. The
                        // layer has room round the square for jumps and sparkles.
                        figure(motion: motion.drawn, face: face, blink: max(swapBlink, motion.blink), rig: frame?.rig)
                            .equatable()
                            .frame(width: side, height: side)
                            .padding(side * Self.overflow)
                            .drawingGroup()
                            .padding(-side * Self.overflow)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                    // Breathing, squash and the alarm's shake move the whole drawn layer, about the feet.
                    .scaleEffect(x: (1 + motion.breathDepth * motion.breath - motion.shrink) * (1 + 0.12 * motion.squash),
                                 y: (1 + motion.breathDepth * motion.breath - motion.shrink) * (1 - 0.12 * motion.squash),
                                 anchor: Self.feet)
                    .rotationEffect(.degrees(motion.lean), anchor: Self.feet)
                    .offset(x: 1.5 * motion.tremble)
                }
                .aspectRatio(1, contentMode: .fit)
                .modifier(BreathingAlong(activity: breathing ? activeBreak : nil, paused: paused))
            }
        }
        // Into or out of a break's own stance as its style changes.
        .animation(still ? Motion.calm(true) : .spring(duration: 0.6 * Motion.speed, bounce: 0.2),
                   value: activeBreak?.style)
        // Pausing a workout drops back to guard quickly.
        .animation(still ? Motion.calm(true) : .spring(duration: (pose == .waiting && workout != nil ? 0.3 : 0.45) * Motion.speed,
                                                       bounce: 0.25), value: pose)
        .animation(.spring(duration: 0.22, bounce: 0.45), value: pressing)
        // Headphones on or off as a focus sound starts or stops.
        .animation(still ? Motion.calm(true) : .spring(duration: 0.45 * Motion.speed, bounce: 0.2), value: listening)
        .overlay { touchAreas }
        .sensoryFeedback(.impact(weight: .light), trigger: crownTaps)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: pokes)
        .modifier(TickAccessibility(pose: pose, crown: crown, onDismiss: onDismiss))
        .onChange(of: pose) { old, new in
            since = .now
            facePose = old
            faceSwap = .now
            // A change caught up on as the app comes back shows as it stands.
            let seen = onScreen && scenePhase == .active && Date.now.timeIntervalSince(activeSince) > 0.5
            // Resuming a workout goes straight back to it, gloves and headphones still on.
            let resuming = workout != nil && new == .working && old == .waiting
            entering = seen && !resuming
            gearingUp = seen && workout != nil && new == .working && !resuming
        }
        .onChange(of: celebration) {
            // Replays the done entry: the jump, the sparkles, the gold.
            guard pose == .done else { return }
            since = .now
            entering = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activeSince = .now }
        }
        .task(id: rejoinsRest) {
            // Stretches done: back to the mug and its steam.
            guard let rejoinsRest else { return }
            try? await Task.sleep(for: .seconds(max(0, rejoinsRest.timeIntervalSinceNow) + 0.05))
            if !Task.isCancelled { breakRefresh += 1 }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }

    }

    // MARK: Touch

    /// The crown and the body take touches, each at least 44 pt; while
    /// ringing, all of Tick does.
    private var touchAreas: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / 100
            let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
            let rig = TickRig(pose)
            if pose == .ringing {
                Button { touch(.body) } label: { Color.clear.contentShape(.rect) }
                    .buttonStyle(TickPressStyle(pressing: .constant(false)))
            } else {
                let body = TickTouch.bodyCenter(rig)
                Button { touch(.body) } label: {
                    Circle().fill(.clear).contentShape(.circle)
                        .frame(width: max(44, 62 * unit), height: max(44, 62 * unit))
                }
                .buttonStyle(TickPressStyle(pressing: .constant(false)))
                .position(x: origin.x + body.x * unit, y: origin.y + body.y * unit)

                let crownPoint = TickTouch.crownCenter(rig)
                Button { touch(.crown) } label: {
                    Circle().fill(.clear).contentShape(.circle)
                        .frame(width: max(44, 26 * unit), height: max(44, 26 * unit))
                }
                .buttonStyle(TickPressStyle(pressing: crown == nil ? .constant(false) : $pressing))
                .position(x: origin.x + crownPoint.x * unit, y: origin.y + crownPoint.y * unit)
            }
        }
        .accessibilityHidden(true)
    }

    private func touch(_ region: TickTouch.Region) {
        switch TickTouch.action(for: region, pose: pose, crownWorks: crown != nil) {
        case .dismissAlarm:
            onDismiss?()
        case .crown:
            crownTaps += 1
            crown?.action()
        case .poke:
            pokedAt = .now
            pokes += 1
        }
    }

    /// The workout's own: punches landing, hard breathing and its puffs,
    /// and the blinks that hide its face changes.
    private func withWorkout(_ motion: TickMotion, _ frame: WorkoutFrame?) -> TickMotion {
        guard let frame else { return motion }
        var motion = motion
        motion.impact = frame.motion.impact
        motion.impactAt = frame.motion.impactAt
        motion.breath = frame.motion.breath
        motion.breathDepth = frame.motion.breathDepth
        motion.puff = frame.motion.puff
        motion.sweat = frame.motion.sweat
        motion.blink = max(motion.blink, frame.motion.blink)
        return motion
    }

    /// A parked thought landing: caught, or a nod mid-combo.
    private func withCatch(_ motion: TickMotion, at date: Date, workout: WorkoutLoops?) -> TickMotion {
        guard let caughtAt else { return motion }
        let midCombo = workout?.move(at: caughtAt) != nil
        return TickCatch.apply(to: motion, at: date.timeIntervalSince(caughtAt), nod: midCombo)
    }

    /// A poke adds a quick squish.
    private func withPoke(_ motion: TickMotion, at date: Date) -> TickMotion {
        guard let pokedAt else { return motion }
        let t = date.timeIntervalSince(pokedAt) / Motion.speed
        guard t >= 0, t < 0.3 else { return motion }
        var motion = motion
        motion.squash += 0.6 * sin(.pi * t / 0.3)
        return motion
    }

    /// How far beyond its square Tick may reach, as a fraction of its size.
    private static let overflow = 0.25

    /// Where Tick stands, in the figure's square.
    private static let feet = UnitPoint(x: 0.5, y: 0.92)

    private func figure(motion: TickMotion, face: TickFace, blink: Double = 0, rig: TickRig? = nil) -> TickFigure {
        var face = face
        // The loop's blink, or eyes the frame itself closes (a stretch, a yawn).
        face.blink = max(face.blink, blink)
        var rig = rig ?? TickRig(pose)
        rig.crownPress = pressing ? 1 : 0
        if listening == false { rig.headphones = 0 }
        return TickFigure(rig: rig, face: face, palette: .standard, motion: motion, progress: ringLeft)
    }

    private var ringLeft: Double {
        switch progress {
        case .sheet: pose.sheetProgress
        case .fixed(let value): value
        }
    }

    /// The face for now: the new state's numbers (they spring), with the
    /// old state's eyes, brows and mouth until the blink has shut.
    private func face(at date: Date, base: TickFace? = nil) -> (TickFace, Double) {
        var face = base ?? TickFace(pose)
        if let pokedAt, date.timeIntervalSince(pokedAt) / Motion.speed < TickTouch.pokeLength,
           date >= pokedAt, pose != .ringing {
            // A giggle.
            face.eyes = .happy
            face.mouth = .openSmile
            return (face, 0)
        }
        guard let faceSwap, let facePose else { return (face, 0) }
        let into = date.timeIntervalSince(faceSwap) / Motion.speed
        guard into < 0.18 else { return (face, 0) }
        if into < 0.07 {
            let old = TickFace(facePose)
            face.eyes = old.eyes
            face.mouth = old.mouth
            face.brows = old.brows
            return (face, into / 0.07)
        }
        return (face, 1 - (into - 0.07) / 0.11)
    }
}

/// Breathing with the halo: the whole drawn Tick grows 4% on each breath
/// in, about its feet, moved by the render server between turns.
private struct BreathingAlong: ViewModifier {
    let activity: TickBreak?
    let paused: Bool

    func body(content: Content) -> some View {
        if let activity, !paused {
            BreathFollower(activity: activity) { fullness, _ in
                content.scaleEffect(1 + 0.04 * fullness, anchor: UnitPoint(x: 0.5, y: 0.92))
            }
        } else {
            content
        }
    }
}

/// A workout made calm, as Reduce Motion and Low Power Mode want it.
private struct CalmLoops {
    let loops: WorkoutLoops

    init(_ loops: WorkoutLoops) {
        var calm = loops
        calm.workout.style = .calm
        self.loops = calm
    }
}

/// The session's combos and sweat, worked out once for its length and
/// seed rather than on every frame.
private final class ComboCache {
    private var made: (ComboScheduler, SweatEmitter)?

    func parts(for workout: TickWorkout) -> (ComboScheduler, SweatEmitter) {
        if let made, made.0.planned == workout.planned, made.0.seed == workout.seed { return made }
        let scheduler = ComboScheduler(planned: workout.planned, seed: workout.seed)
        let parts = (scheduler, SweatEmitter(planned: workout.planned, seed: workout.seed, scheduler: scheduler))
        made = parts
        return parts
    }
}

/// Reports the press, so the crown can sink while held.
private struct TickPressStyle: ButtonStyle {
    @Binding var pressing: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in pressing = pressed }
    }
}

/// Tick as one VoiceOver element when it does something: "Tick", what
/// it's doing, and the crown's action (or stopping the alarm). Otherwise
/// decorative: the dial beside it says it all.
private struct TickAccessibility: ViewModifier {
    let pose: TickPose
    let crown: (label: String, action: () -> Void)?
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        if crown == nil && onDismiss == nil {
            content.accessibilityHidden(true)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Tick"))
                .accessibilityValue(pose.spokenState)
                .accessibilityActions {
                    if pose == .ringing, let onDismiss {
                        Button(String(localized: "Stop alarm"), action: onDismiss)
                    } else if let crown {
                        Button(crown.label, action: crown.action)
                    }
                }
        }
    }
}
