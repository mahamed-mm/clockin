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

    /// Colour changes between focus and break.
    static func tint(_ reduceMotion: Bool) -> Animation {
        .easeInOut(duration: (reduceMotion ? 0.2 : 0.6) * speed)
    }
}

@MainActor
extension AnyTransition {
    /// Fade and rise a few points; a plain fade with Reduce Motion.
    static func rise(_ reduceMotion: Bool, delay: Double = 0) -> AnyTransition {
        let base: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10))
        return base.animation(Motion.calm(reduceMotion).delay(reduceMotion ? 0 : delay * Motion.speed))
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
