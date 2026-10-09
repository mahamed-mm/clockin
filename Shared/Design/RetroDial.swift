import SwiftUI

/// Kitchen-timer dial: tick ring, a gradient arc with a knob at its tip, and
/// ticks that light up inside the arc. Used by the app, the widget, and the
/// Live Activity.
///
/// `value` is the arc's length (0...1) drawn clockwise from 12 o'clock.
/// The view is `Animatable`, so springing `value` winds and unwinds the arc.
struct RetroDial: View, Animatable {
    var value: Double
    var tint: Color
    var glowTint: Color = Retro.mustard
    var showsTicks = true
    var showsKnob = true
    var lineWidthRatio: CGFloat = 0.075

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side / 2
            let line = side * lineWidthRatio
            let arcValue = min(max(value, 0), 1)

            // Face
            context.fill(circle(center, radius), with: .color(Retro.paperDeep))

            // Ticks, lit inside the arc
            if showsTicks {
                for i in 0..<60 {
                    let fraction = Double(i) / 60
                    let angle = fraction * 2 * .pi
                    let major = i % 5 == 0
                    let lit = fraction < arcValue - 0.0001
                    let outer = radius * 0.94
                    let inner = outer - radius * (major ? 0.11 : 0.05)
                    var tick = Path()
                    tick.move(to: point(center, outer, angle))
                    tick.addLine(to: point(center, inner, angle))
                    let color = lit ? tint : Retro.ink.opacity(major ? 0.85 : 0.35)
                    context.stroke(tick, with: .color(color),
                                   style: StrokeStyle(lineWidth: side * (major ? 0.012 : 0.006),
                                                      lineCap: .round))
                }
            }

            // Track
            let arcRadius = radius * Self.arcRadiusRatio(showsTicks: showsTicks)
            context.stroke(circle(center, arcRadius), with: .color(Retro.ink.opacity(0.08)),
                           style: StrokeStyle(lineWidth: line))

            // Arc
            if arcValue > 0.001 {
                var arc = Path()
                arc.addArc(center: center, radius: arcRadius, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * arcValue), clockwise: false)
                // Warm toward the knob: tint at the tail, glow at the tip. The
                // wrap back to 12 o'clock stays tint so the tail's cap is clean.
                let tip = max(arcValue, 0.02)
                let gradient = Gradient(stops: [
                    .init(color: tint, location: 0),
                    .init(color: tint, location: tip * 0.7),
                    .init(color: glowTint, location: tip),
                    .init(color: tint, location: min(1, tip + 0.0001)),
                ])
                context.stroke(arc, with: .conicGradient(gradient, center: center, angle: .degrees(-90)),
                               style: StrokeStyle(lineWidth: line, lineCap: .round))
            }

            // Knob at the arc's tip
            if showsKnob {
                let tip = point(center, arcRadius, arcValue * 2 * .pi)
                let knobRadius = line * 0.62
                context.fill(circle(tip, knobRadius), with: .color(Retro.paper))
                context.stroke(circle(tip, knobRadius), with: .color(Retro.ink.opacity(0.85)),
                               lineWidth: max(1, line * 0.14))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Arc radius as a fraction of the dial's half-width; used to place overlays on the arc.
    static func arcRadiusRatio(showsTicks: Bool) -> CGFloat { showsTicks ? 0.66 : 0.76 }

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
