import SwiftUI

/// Tick in the app: the drawing plus a few moments of motion when the pose
/// changes, then stillness, so a screen at rest draws nothing. Still with
/// Reduce Motion or when the phone is saving power. Decorative: the dial
/// beside it is what VoiceOver reads.
struct TickView: View {
    let pose: TickPose
    /// Increments when a focus session completes, for the "ding" hop.
    var celebration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            figure
                .id(pose)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .animation(Motion.calm(reduceMotion), value: pose)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var figure: some View {
        if reduceMotion || services.power.isConstrained {
            TickFigure(pose: pose, palette: .retro)
        } else {
            let a = Amplitudes(pose)
            Color.clear.keyframeAnimator(initialValue: TickMotion.still, trigger: Moment(pose: pose, celebration: celebration)) { _, motion in
                TickFigure(pose: pose, palette: .retro, motion: motion)
            } keyframes: { [speed = Motion.speed] _ in
                // Two blinks, a few seconds apart.
                KeyframeTrack(\.blink) {
                    LinearKeyframe(0, duration: 1.4 * speed)
                    LinearKeyframe(a.blink, duration: 0.08 * speed)
                    LinearKeyframe(0, duration: 0.12 * speed)
                    LinearKeyframe(0, duration: 2.6 * speed)
                    LinearKeyframe(a.blink, duration: 0.08 * speed)
                    LinearKeyframe(0, duration: 0.12 * speed)
                }
                // A slow bob, three times.
                KeyframeTrack(\.bob) {
                    CubicKeyframe(-a.bob, duration: 0.9 * speed)
                    CubicKeyframe(0, duration: 0.9 * speed)
                    CubicKeyframe(-a.bob, duration: 0.9 * speed)
                    CubicKeyframe(0, duration: 0.9 * speed)
                    CubicKeyframe(-a.bob, duration: 0.9 * speed)
                    CubicKeyframe(0, duration: 0.9 * speed)
                }
                // Steam rising from the mug, three times.
                KeyframeTrack(\.steam) {
                    LinearKeyframe(a.steam * 0.999, duration: 1.6 * speed)
                    LinearKeyframe(0, duration: 0.001)
                    LinearKeyframe(a.steam * 0.999, duration: 1.6 * speed)
                    LinearKeyframe(0, duration: 0.001)
                    LinearKeyframe(a.steam * 0.999, duration: 1.6 * speed)
                    LinearKeyframe(0, duration: 0.001)
                }
                // The "ding" hop, and a smaller one after.
                KeyframeTrack(\.hop) {
                    SpringKeyframe(a.hop, duration: 0.25 * speed, spring: .snappy)
                    CubicKeyframe(0, duration: 0.3 * speed)
                    SpringKeyframe(a.hop * 0.5, duration: 0.2 * speed, spring: .snappy)
                    CubicKeyframe(0, duration: 0.3 * speed)
                }
                // A little lean back and forth with a wave.
                KeyframeTrack(\.lean) {
                    CubicKeyframe(a.lean, duration: 0.35 * speed)
                    CubicKeyframe(-a.lean, duration: 0.5 * speed)
                    CubicKeyframe(a.lean, duration: 0.5 * speed)
                    CubicKeyframe(0, duration: 0.35 * speed)
                }
            }
        }
    }

    /// What restarts the motion: a new pose, or a new completion.
    private struct Moment: Equatable {
        var pose: TickPose
        var celebration: Int
    }

    /// How much of each motion a pose gets.
    private struct Amplitudes {
        var blink = 0.0, bob = 0.0, steam = 0.0, hop = 0.0, lean = 0.0

        init(_ pose: TickPose) {
            switch pose {
            case .ready: blink = 1; bob = 0.8
            case .working: blink = 1; bob = 1.2
            case .waiting: blink = 1
            case .done: hop = 1
            case .streak: hop = 0.5
            case .onBreak: steam = 1; bob = 0.6
            case .hello: blink = 1; lean = 3
            case .interrupted: blink = 1
            case .ringing, .sleeping: bob = 0.6
            }
        }
    }
}
