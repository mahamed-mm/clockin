import SwiftUI
import WidgetKit

/// Tick as a still, for the Lock Screen, Dynamic Island, StandBy and the
/// widget. A new pose fades in. On tinted and clear Home Screens Tick is
/// drawn in one tone, like the dials.
struct TickBadge: View {
    let pose: TickPose
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        TickFigure(pose: pose, palette: renderingMode == .fullColor ? .retro : .monochrome)
            .id(pose)
            .transition(.opacity)
            .accessibilityHidden(true)
    }
}

extension TickPalette {
    /// One tone, for accented and vibrant rendering: the shapes still read
    /// by brightness.
    static let monochrome = TickPalette(face: .white.opacity(0.18), rim: .white, features: .white,
                                        limbs: .white, prop: .white.opacity(0.85), accent: .white.opacity(0.7),
                                        shadow: .clear)
}
