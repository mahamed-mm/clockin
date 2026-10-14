import SwiftUI
import WidgetKit

/// Tick as a still, for the Lock Screen, Dynamic Island, StandBy and the
/// widget. A new pose fades in. On tinted and clear Home Screens Tick is
/// drawn in one tone, like the dials.
///
/// Tick is drawn into one small bitmap here, in the extension, and handed
/// over as an image: the simplest thing for the system to show on every
/// Live Activity surface.
struct TickBadge: View {
    let pose: TickPose
    /// Nil picks the detail from the size.
    var detail: TickDetail? = nil
    /// The ring's time left; the character sheet's own when nil.
    var progress: Double? = nil
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
        TickFigure(pose: pose, palette: palette, detail: detail, progress: progress)
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

extension TickBadge {
    var palette: TickPalette { renderingMode == .fullColor ? .standard : .monochrome }
}

/// Tick on the Lock Screen and in the Dynamic Island, where it can't
/// move: its face, still, inside a live ring the system draws, so the time
/// left keeps moving. The ring drains through focus and fills through a
/// break; it's gold when done and red while the alarm rings. With room,
/// the crown sits on top.
struct TickLiveGlyph: View {
    let pose: TickPose
    let reading: TimerReading
    let phase: SessionPhase
    var crown = true
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ringSide = crown ? side * 0.84 : side
            ZStack(alignment: .top) {
                ring
                    .overlay { TickBadge(pose: pose, detail: .face).padding(ringSide * 0.09) }
                    .frame(width: ringSide, height: ringSide)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                if crown { crownShape(width: ringSide * 0.42) }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var palette: TickPalette { renderingMode == .fullColor ? .standard : .monochrome }

    private var tint: Color {
        switch pose {
        case .done, .streak: palette.doneGold
        case .ringing: palette.ringingRed
        default: palette.ring
        }
    }

    @ViewBuilder
    private var ring: some View {
        Group {
            switch (pose, reading) {
            case (.ringing, _), (_, .done):
                ProgressView(value: 1)
            case (_, .running(let range)):
                ProgressView(timerInterval: range, countsDown: phase == .focus) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            case (_, .paused(let fraction, _)):
                ProgressView(value: phase == .focus ? fraction : 1 - fraction)
            }
        }
        .progressViewStyle(.circular)
        .tint(tint)
    }

    /// The crown on its stem, in the ring's colours.
    private func crownShape(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: width * 0.18)
                .fill(palette.crown)
                .overlay { RoundedRectangle(cornerRadius: width * 0.18).strokeBorder(palette.eyes, lineWidth: max(1, width * 0.08)) }
                .frame(width: width, height: width * 0.5)
            Rectangle().fill(palette.ring).frame(width: width * 0.36, height: width * 0.34)
        }
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
