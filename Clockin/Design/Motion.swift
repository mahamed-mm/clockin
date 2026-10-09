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

/// Slow retro-clock blink used while paused.
struct BlinkWhilePaused: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([1.0, 0.4]) { view, opacity in
                view.opacity(opacity)
            } animation: { [speed = Motion.speed] _ in .easeInOut(duration: 1.2 * speed) }
        } else {
            content.opacity(active ? 0.55 : 1)
        }
    }
}
