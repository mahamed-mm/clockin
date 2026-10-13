import SwiftUI

/// Shared animation curves. Every curve collapses to a short fade when
/// Reduce Motion is on.
@MainActor
enum Motion {
    /// Duration multiplier: 1, or 4 with the debug "Slow animations" switch.
    static var speed: Double {
        #if DEBUG
        DevSettings.shared.slowAnimations ? 4 : 1
        #else
        1
        #endif
    }

    /// Default for layout and content changes.
    static func calm(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2 * speed) : .smooth(duration: 0.45 * speed)
    }

    /// Small, quick changes such as rolling digits.
    static func snappy(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15 * speed) : .snappy(duration: 0.3 * speed)
    }

    /// The dial winding up or rewinding, like turning a kitchen timer.
    static func wind(_ reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2 * speed)
            : .spring(response: 0.7 * speed, dampingFraction: 0.78)
    }

    /// The screen stepping back round a running dial, and coming forward
    /// again (faster, since a touch asked for it).
    static func stepBack(_ reduceMotion: Bool, returning: Bool) -> Animation {
        .easeInOut(duration: (returning ? 0.25 : reduceMotion ? 0.4 : 1.2) * speed)
    }

    /// Colour changes between focus and break.
    static func tint(_ reduceMotion: Bool) -> Animation {
        .easeInOut(duration: (reduceMotion ? 0.2 : 0.6) * speed)
    }
}

extension Motion {
    /// Delay for the nth item of something that fills in: 40 ms apart,
    /// capped at ten so a long list doesn't keep you waiting. `after` waits
    /// first. No delay with Reduce Motion.
    static func stagger(_ index: Int, after: Double = 0, _ reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : (after + 0.04 * Double(min(index, 10))) * speed
    }

    /// How long the completion celebration plays before the summary fills in.
    static let afterCelebration = 0.25
}

@MainActor
extension AnyTransition {
    /// Content arriving: fade and rise a few points; a plain fade with
    /// Reduce Motion. `delay` comes from `Motion.stagger`.
    static func rise(_ reduceMotion: Bool, delay: Double = 0) -> AnyTransition {
        let base: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10))
        return base.animation(Motion.calm(reduceMotion).delay(delay))
    }

    /// A small control or symbol appearing in place (+5 min, the seal).
    static func pop(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity)
    }

    /// A bar that comes and goes near the bottom (the undo bars).
    static func bar(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: Space.m).combined(with: .opacity)
    }
}

/// The dial's "ding" when focus completes: a 3.5% swell that springs back,
/// timed to the completion haptic. Still with Reduce Motion.
struct CelebrationPulse: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { [speed = Motion.speed, reduceMotion] _ in
            CubicKeyframe(1.0, duration: 0.05 * speed)
            CubicKeyframe(reduceMotion ? 1.0 : 1.035, duration: 0.18 * speed)
            SpringKeyframe(1.0, duration: 0.6 * speed)
        }
    }
}

/// Three slow breaths of opacity, then rest, so a waiting screen soon draws
/// nothing (the idle knob's halo). Resting only with Reduce Motion or Low
/// Power Mode.
struct BreatheThrice: ViewModifier {
    var low: Double
    var high: Double
    var resting: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services
    @State private var breathe = false

    func body(content: Content) -> some View {
        if reduceMotion || services.power.isConstrained {
            content.opacity(resting)
        } else {
            content.keyframeAnimator(initialValue: resting, trigger: breathe) { view, opacity in
                view.opacity(opacity)
            } keyframes: { [speed = Motion.speed, low, high, resting] _ in
                CubicKeyframe(low, duration: 1.5 * speed)
                CubicKeyframe(high, duration: 3 * speed)
                CubicKeyframe(low, duration: 3 * speed)
                CubicKeyframe(high, duration: 3 * speed)
                CubicKeyframe(low, duration: 3 * speed)
                CubicKeyframe(high, duration: 3 * speed)
                CubicKeyframe(resting, duration: 1.5 * speed)
            }
            .onAppear { breathe.toggle() }
        }
    }
}

/// Slow retro-clock blink when a timer pauses: three blinks, then it stays
/// dimmed, so a paused screen draws nothing.
struct BlinkWhilePaused: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services
    @State private var blink = false
    private static let dimmed = 0.55

    func body(content: Content) -> some View {
        if active && !reduceMotion && !services.power.isConstrained {
            content.keyframeAnimator(initialValue: Self.dimmed, trigger: blink) { view, opacity in
                view.opacity(opacity)
            } keyframes: { [speed = Motion.speed] _ in
                CubicKeyframe(1.0, duration: 0.6 * speed)
                CubicKeyframe(0.4, duration: 1.2 * speed)
                CubicKeyframe(1.0, duration: 1.2 * speed)
                CubicKeyframe(0.4, duration: 1.2 * speed)
                CubicKeyframe(1.0, duration: 1.2 * speed)
                CubicKeyframe(0.4, duration: 1.2 * speed)
                CubicKeyframe(Self.dimmed, duration: 0.6 * speed)
            }
            .onAppear { blink.toggle() }
        } else {
            content.opacity(active ? Self.dimmed : 1)
        }
    }
}
