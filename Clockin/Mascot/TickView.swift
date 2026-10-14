import SwiftUI

private extension TickMotion {
    /// What the parts draw: the motion without what moves the whole figure.
    var drawn: TickMotion {
        var motion = self
        motion.breath = 0
        motion.lean = 0
        motion.tremble = 0
        motion.blink = 0
        return motion
    }
}

/// Frames for Tick's loops: 30 a second while something moves (and
/// through the face-swap blink after a change), then none until the next
/// blink, tap or hop.
struct TickLoopSchedule: TimelineSchedule {
    let loops: TickLoops
    let since: Date
    let paused: Bool
    /// The debug menu's slow motion.
    let speed: Double

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator {
            guard let date = next else { return nil }
            guard !paused, mode != .lowFrequency else {
                next = nil
                return date
            }
            let frame = date.timeIntervalSince(since) / speed + 1 / 30
            // The face swaps behind a blink in the first 0.18 s.
            let soonest = frame < 0.2 ? frame : loops.nextMovement(from: frame)
            next = since.addingTimeInterval(soonest * speed)
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
/// (then states cross-fade). Decorative: the dial beside it is what
/// VoiceOver reads.
struct TickView: View {
    let pose: TickPose
    var progress: TickProgress = .sheet
    /// Increments when a focus session completes, for the "ding" hop.
    var celebration = 0

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
    @State private var seed = Double.random(in: 0..<100)

    private var reduceMotion: Bool { systemReduceMotion || galleryReduceMotion }
    private var still: Bool { reduceMotion || services.power.isConstrained }
    private var paused: Bool { !onScreen || scenePhase != .active }
    private var loops: TickLoops { TickLoops(pose: pose, seed: seed) }

    var body: some View {
        Group {
            if still {
                // Cross-fades between stills.
                figure(motion: .still, face: TickFace(pose))
                    .id(pose)
                    .transition(.opacity)
            } else {
                // Frames only while something moves (30 a second), none between.
                TimelineView(TickLoopSchedule(loops: loops, since: since, paused: paused, speed: Motion.speed)) { context in
                    let elapsed = context.date.timeIntervalSince(since) / Motion.speed
                    let motion = paused ? TickMotion.still : loops.motion(at: elapsed)
                    let (face, swapBlink) = face(at: context.date)
                    figure(motion: motion.drawn, face: face, blink: max(swapBlink, motion.blink))
                        .equatable()
                        // Drawn once into a layer, so moving it costs no redraw.
                        .drawingGroup()
                        // Breathing and the alarm's shake move the whole drawn layer, about the feet.
                        .scaleEffect(1 + 0.02 * motion.breath, anchor: Self.feet)
                        .rotationEffect(.degrees(motion.lean), anchor: Self.feet)
                        .offset(x: 1.5 * motion.tremble)
                }
            }
        }
        .animation(still ? Motion.calm(true) : .spring(duration: 0.45 * Motion.speed, bounce: 0.25), value: pose)
        .onChange(of: pose) { old, _ in
            since = .now
            facePose = old
            faceSwap = .now
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }

        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where Tick stands, in the figure's square.
    private static let feet = UnitPoint(x: 0.5, y: 0.92)

    private func figure(motion: TickMotion, face: TickFace, blink: Double = 0) -> TickFigure {
        var face = face
        face.blink = blink
        return TickFigure(rig: TickRig(pose), face: face, palette: .standard, motion: motion, progress: ringLeft)
    }

    private var ringLeft: Double {
        switch progress {
        case .sheet: pose.sheetProgress
        case .fixed(let value): value
        }
    }

    /// The face for now: the new state's numbers (they spring), with the
    /// old state's eyes, brows and mouth until the blink has shut.
    private func face(at date: Date) -> (TickFace, Double) {
        var face = TickFace(pose)
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
