import SwiftUI
import WidgetKit

/// Tick as a still, for the Lock Screen, Dynamic Island, StandBy and the
/// widget. A new pose fades in. On tinted and clear Home Screens Tick is
/// drawn in one tone, like the dials.
///
/// Tick is drawn into a bitmap here, in the extension, and handed over as
/// an image: on a real iPhone the Dynamic Island leaves a Canvas blank
/// (the simulator and the Lock Screen draw it).
struct TickBadge: View {
    let pose: TickPose
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Group {
                if let image = rendered(side: side) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                } else {
                    figure
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .id(pose)
        .transition(.opacity)
        .accessibilityHidden(true)
    }

    private var figure: TickFigure {
        TickFigure(pose: pose, palette: renderingMode == .fullColor ? .standard : .monochrome)
    }

    /// Tick at this size, keeping the detail the size calls for.
    private func rendered(side: CGFloat) -> UIImage? {
        guard side > 0 else { return nil }
        // The renderer has its own environment: the asset colours need this one's appearance.
        let renderer = ImageRenderer(content: figure.frame(width: side, height: side)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale
        renderer.isOpaque = false
        return renderer.uiImage
    }
}

extension TickPalette {
    /// One tone, for accented and vibrant rendering, where the system
    /// keeps only each colour's brightness: the shapes still read.
    static var monochrome: TickPalette {
        let tone = Color.white
        return TickPalette(face: tone.opacity(0.18), ring: tone, track: tone.opacity(0.45), cap: tone, crown: tone.opacity(0.85),
                           eyes: tone, cheeks: tone.opacity(0.2), limbs: tone, doneGold: tone, ringingRed: tone,
                           effects: tone.opacity(0.7), shadow: .clear)
    }
}
