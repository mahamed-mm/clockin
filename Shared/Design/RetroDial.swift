import SwiftUI
import WidgetKit

/// Kitchen-timer dial: tick ring, a gradient arc with a knob at its tip, and
/// ticks that light up inside the arc. Used by the app, the widget, and the
/// Live Activity.
///
/// `value` is the arc's length (0...1) drawn clockwise from 12 o'clock.
/// The view is `Animatable`, so springing `value` winds and unwinds the arc.
///
/// Drawn in two layers so a tinted or clear Home Screen can render it: the
/// face, ticks and track, then the progress (lit ticks, arc, knob) marked
/// accentable. Outside full colour the opaque face is left out, since the
/// system would flatten it into a solid disc.
struct RetroDial: View, Animatable {
    var value: Double
    var tint: Color
    var glowTint: Color = Retro.mustard
    var showsTicks = true
    var showsKnob = true
    var lineWidthRatio: CGFloat = 0.075
    /// A faint gloss on the track's upper left, like light on Bakelite. The
    /// app's dial only; the arc's colours mean the same either way.
    var highlight = false
    /// Draws the arc as quarters in the set's colours, one per session of
    /// four, for a day's sessions; the default is one tinted sweep.
    var setColors = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let showsFace = renderingMode == .fullColor
        ZStack {
            Canvas { context, size in
                drawBase(in: &context, Geometry(size: size, dial: self), showsFace: showsFace)
            }
            Canvas { context, size in
                drawProgress(in: &context, Geometry(size: size, dial: self))
            }
            .widgetAccentable()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The quarters a set-coloured arc of `value` draws: each session of
    /// four, with a small gap between them.
    nonisolated static func setSegments(value: Double) -> [(position: Int, from: Double, to: Double)] {
        let gap = 0.015
        return (0..<4).compactMap { position in
            let from = Double(position) / 4
            let to = min(value, from + 0.25)
            guard to - from > 0.001 else { return nil }
            return (position, from + gap, max(from + gap, to - gap))
        }
    }

    /// Arc radius as a fraction of the dial's half-width; used to place overlays on the arc.
    nonisolated static func arcRadiusRatio(showsTicks: Bool) -> CGFloat { showsTicks ? 0.66 : 0.76 }

    private struct Geometry {
        let center: CGPoint
        let radius: CGFloat
        let side: CGFloat
        let line: CGFloat
        let arcRadius: CGFloat
        let arcValue: Double

        init(size: CGSize, dial: RetroDial) {
            side = min(size.width, size.height)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            radius = side / 2
            line = side * dial.lineWidthRatio
            arcRadius = radius * RetroDial.arcRadiusRatio(showsTicks: dial.showsTicks)
            arcValue = min(max(dial.value, 0), 1)
        }
    }

    /// Face, unlit ticks and the empty track.
    private func drawBase(in context: inout GraphicsContext, _ g: Geometry, showsFace: Bool) {
        if showsFace {
            context.fill(circle(g.center, g.radius), with: .color(Retro.paperDeep))
        }
        if showsTicks {
            drawTicks(in: &context, g, lit: false)
        }
        context.stroke(circle(g.center, g.arcRadius), with: .color(Retro.ink.opacity(0.08)),
                       style: StrokeStyle(lineWidth: g.line))
        if highlight && showsFace {
            // Along the track's outer edge, from about 8 to 11 o'clock, fading at both ends.
            var gloss = Path()
            gloss.addArc(center: g.center, radius: g.arcRadius + g.line * 0.22, startAngle: .degrees(-210),
                         endAngle: .degrees(-100), clockwise: false)
            let from = point(g.center, g.arcRadius, -.pi * 0.66), to = point(g.center, g.arcRadius, -.pi * 0.06)
            let shine = Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                         .init(color: .white.opacity(0.12), location: 0.5),
                                         .init(color: .white.opacity(0), location: 1)])
            context.stroke(gloss, with: .linearGradient(shine, startPoint: from, endPoint: to),
                           style: StrokeStyle(lineWidth: g.line * 0.28, lineCap: .round))
        }
    }

    /// Ticks inside the arc, the arc, and the knob at its tip.
    private func drawProgress(in context: inout GraphicsContext, _ g: Geometry) {
        if showsTicks {
            drawTicks(in: &context, g, lit: true)
        }

        if setColors {
            for segment in Self.setSegments(value: g.arcValue) {
                var arc = Path()
                arc.addArc(center: g.center, radius: g.arcRadius, startAngle: .degrees(-90 + 360 * segment.from),
                           endAngle: .degrees(-90 + 360 * segment.to), clockwise: false)
                context.stroke(arc, with: .color(Retro.setColor(position: segment.position)),
                               style: StrokeStyle(lineWidth: g.line, lineCap: .butt))
            }
        } else if g.arcValue > 0.001 {
            var arc = Path()
            arc.addArc(center: g.center, radius: g.arcRadius, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * g.arcValue), clockwise: false)
            // Warm toward the knob: tint at the tail, glow at the tip. The
            // wrap back to 12 o'clock stays tint so the tail's cap is clean.
            let tip = max(g.arcValue, 0.02)
            let gradient = Gradient(stops: [
                .init(color: tint, location: 0),
                .init(color: tint, location: tip * 0.7),
                .init(color: glowTint, location: tip),
                .init(color: tint, location: min(1, tip + 0.0001)),
            ])
            context.stroke(arc, with: .conicGradient(gradient, center: g.center, angle: .degrees(-90)),
                           style: StrokeStyle(lineWidth: g.line, lineCap: .round))
        }

        if showsKnob {
            let tip = point(g.center, g.arcRadius, g.arcValue * 2 * .pi)
            let knobRadius = g.line * 0.62
            context.fill(circle(tip, knobRadius), with: .color(Retro.paper))
            context.stroke(circle(tip, knobRadius), with: .color(Retro.ink.opacity(0.85)),
                           lineWidth: max(1, g.line * 0.14))
        }
    }

    /// The ticks inside the arc (`lit`) or outside it.
    private func drawTicks(in context: inout GraphicsContext, _ g: Geometry, lit: Bool) {
        for i in 0..<60 {
            let fraction = Double(i) / 60
            guard (fraction < g.arcValue - 0.0001) == lit else { continue }
            let angle = fraction * 2 * .pi
            let major = i % 5 == 0
            let outer = g.radius * 0.94
            let inner = outer - g.radius * (major ? 0.11 : 0.05)
            var tick = Path()
            tick.move(to: point(g.center, outer, angle))
            tick.addLine(to: point(g.center, inner, angle))
            let color = lit ? tint : Retro.ink.opacity(major ? 0.85 : 0.35)
            context.stroke(tick, with: .color(color),
                           style: StrokeStyle(lineWidth: g.side * (major ? 0.012 : 0.006), lineCap: .round))
        }
    }

    private func circle(_ center: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private func point(_ center: CGPoint, _ r: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle))
    }
}

#Preview {
    VStack(spacing: 24) {
        RetroDial(value: 0.62, tint: Retro.orange)
        RetroDial(value: 0.3, tint: Retro.avocado, showsTicks: false, lineWidthRatio: 0.12)
            .frame(width: 120)
    }
    .padding(40)
    .background(PaperBackground())
}
