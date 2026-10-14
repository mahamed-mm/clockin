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
    let paused: Bool
    /// The debug menu's slow motion.
    let speed: Double
    /// A workout under way: combos move to the session's own clock.
    var workout: WorkoutLoops? = nil

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
            let soonest = frame < 0.2 || poking ? frame : loops.nextMovement(from: frame)
            var upcoming = since.addingTimeInterval(soonest * speed)
            if let workout {
                // The next combo frame, or the next combo's start.
                let step = date.addingTimeInterval(workout.frameInterval(at: date))
                upcoming = min(upcoming, max(step, workout.nextMovement(from: step)))
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

    private var reduceMotion: Bool { systemReduceMotion || galleryReduceMotion }
    private var still: Bool { reduceMotion || services.power.isConstrained }
    private var paused: Bool { !onScreen || scenePhase != .active }
    private var loops: TickLoops {
        TickLoops(pose: pose, seed: seed, entering: entering, breathes: workoutLoops == nil)
    }
    /// The workout, while working through one.
    private var workoutLoops: WorkoutLoops? {
        guard pose == .working, let workout, workout.style == .workout else { return nil }
        let (scheduler, sweat) = combos.parts(for: workout)
        return WorkoutLoops(workout: workout, scheduler: scheduler, sweat: sweat)
    }

    var body: some View {
        Group {
            if still {
                // Cross-fades between stills; a poke still changes the face.
                TimelineView(.explicit(pokedAt.map { [$0, $0.addingTimeInterval(TickTouch.pokeLength)] } ?? [])) { context in
                    let frame = workoutLoops.map { WorkoutFrame(params: WorkoutParams($0.workout.energy(at: context.date))) }
                    figure(motion: .still, face: face(at: context.date, base: frame?.face).0, rig: frame?.rig)
                }
                .id(pose)
                .transition(.opacity)
            } else {
                // Frames only while something moves (30 a second), none between.
                let workoutLoops = workoutLoops
                TimelineView(TickLoopSchedule(loops: loops, since: since, pokedAt: pokedAt, paused: paused,
                                              speed: Motion.speed, workout: workoutLoops)) { context in
                    let elapsed = context.date.timeIntervalSince(since) / Motion.speed
                    let frame = workoutLoops?.frame(at: context.date)
                    let motion = paused ? TickMotion.still : withPoke(withWorkout(loops.motion(at: elapsed), frame), at: context.date)
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
            }
        }
        .animation(still ? Motion.calm(true) : .spring(duration: 0.45 * Motion.speed, bounce: 0.25), value: pose)
        .animation(.spring(duration: 0.22, bounce: 0.45), value: pressing)
        .overlay { touchAreas }
        .sensoryFeedback(.impact(weight: .light), trigger: crownTaps)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: pokes)
        .modifier(TickAccessibility(pose: pose, crown: crown, onDismiss: onDismiss))
        .onChange(of: pose) { old, _ in
            since = .now
            facePose = old
            faceSwap = .now
            // A change caught up on as the app comes back shows as it stands.
            entering = onScreen && scenePhase == .active && Date.now.timeIntervalSince(activeSince) > 0.5
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
        face.blink = blink
        var rig = rig ?? TickRig(pose)
        rig.crownPress = pressing ? 1 : 0
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
