import SwiftUI

/// 70s celebration: the four stripe colours radiate out from the dial as
/// rings from the dial's rim, staggered, then fade. Timed to the completion haptic.
struct Sunburst: View {
    /// Increment to play once.
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ring {
        var scale: CGFloat = 0.98
        var opacity: Double = 0
    }

    var body: some View {
        if !reduceMotion {
            let speed = Motion.speed
            ZStack {
                ForEach(Array(Retro.stripes.reversed().enumerated()), id: \.offset) { index, color in
                    Circle()
                        .stroke(color, lineWidth: 7)
                        .keyframeAnimator(initialValue: Ring(), trigger: trigger) { content, ring in
                            content
                                .scaleEffect(ring.scale)
                                .opacity(ring.opacity)
                        } keyframes: { _ in
                            let delay = 0.14 * Double(index) * speed
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(0.98, duration: delay)
                                CubicKeyframe(1.3 + 0.05 * CGFloat(index), duration: 0.95 * speed)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0, duration: delay)
                                LinearKeyframe(0.85, duration: 0.12 * speed)
                                LinearKeyframe(0, duration: 0.83 * speed)
                            }
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
