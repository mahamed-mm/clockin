import SwiftUI

/// Tick drawn in Tick units (a 100-unit square). Each part is its own
/// layer, named as a rig would name it: ground, chair, legs, headphones,
/// crown, ring, face, eyebrow hand, eyes, mouth, arms, props, effects.
struct TickDrawing {
    var pose: TickPose
    var palette: TickPalette
    var motion: TickMotion
    var detail: TickDetail

    private let radius = 27.0
    private let rimWidth = 7.0
    private let ground = 92.0

    // MARK: Pose table

    /// Where the body's centre sits.
    private var centerY: Double {
        switch pose {
        case .done: 46 - 6 * motion.hop
        case .waiting, .interrupted: 55
        case .onBreak: 54
        case .sleeping: 60
        case .working: 53
        default: 52
        }
    }

    /// Lean in degrees, clockwise.
    private var poseLean: Double {
        switch pose {
        case .ready: 4
        case .working: 7
        case .onBreak: -16
        case .hello: -7
        case .sleeping: -10
        case .waiting: -6
        default: 0
        }
    }

    /// Squash and stretch, about the feet.
    private var poseScale: (x: Double, y: Double) {
        switch pose {
        case .done: (0.95, 1.07)
        case .ringing: (1.08, 0.92)
        default: (1, 1)
        }
    }

    /// The ring's time left: full when ready, draining while working,
    /// empty when the time is up, refilling on a break.
    private var ringLeft: Double {
        if let ring = motion.ring { return min(1, max(0, ring)) }
        switch pose {
        case .ready, .hello, .streak, .sleeping: return 1
        case .working, .waiting: return 0.6
        case .done, .ringing: return 0
        case .onBreak: return 0.5
        case .interrupted: return 0.4
        }
    }

    /// The eyebrow hand's angle in degrees from straight up, clockwise.
    private var browAngle: Double {
        switch pose {
        case .ready: 28
        case .working: -48
        case .waiting: 45
        case .done: 0
        case .onBreak: 75
        case .ringing: 8 * motion.tremble
        case .hello: 35
        case .interrupted: -20
        case .streak: 12
        case .sleeping: 105
        }
    }

    private enum EyeStyle { case eager, down, halfLid, happy, sleepy, wide, softDown, closed }

    private var eyeStyle: EyeStyle {
        switch pose {
        case .ready, .hello: .eager
        case .working: .down
        case .waiting: .halfLid
        case .done, .streak: .happy
        case .onBreak: .sleepy
        case .ringing: .wide
        case .interrupted: .softDown
        case .sleeping: .closed
        }
    }

    private var handmade: Bool { if case .handmade = detail { true } else { false } }
    private var limbWidth: Double { handmade ? 3.8 : 5 }
    private var legWidth: Double { handmade ? 4.8 : 6 }
    /// The crown and eyebrow sit a touch off centre when hand-made.
    private var shift: Double { handmade ? 1.2 : 0 }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext) {
        if case .glyph(let mouth) = detail {
            drawGlyph(mouth: mouth, in: &context)
            return
        }
        drawGround(in: &context)

        // On a break the legs stay put on the ground while the body leans back.
        if pose == .onBreak { drawLegs(in: &context) }

        var figure = context
        figure.translateBy(x: 1.5 * motion.tremble, y: motion.bob)
        let pivot = pose == .onBreak ? CGPoint(x: 50, y: centerY + 22) : CGPoint(x: 50, y: ground)
        figure.translateBy(x: pivot.x, y: pivot.y)
        figure.rotate(by: .degrees(poseLean + motion.lean))
        figure.scaleBy(x: poseScale.x, y: poseScale.y)
        figure.translateBy(x: -pivot.x, y: -pivot.y)

        if pose != .onBreak { drawLegs(in: &figure) }
        drawEffectsBehind(in: &figure)
        if pose == .working { drawHeadphoneBand(in: &figure) }
        drawCrown(in: &figure)
        drawRing(in: &figure)
        // Waiting raises one plain brow instead of the clock-hand brow.
        if pose != .waiting { drawBrowHand(in: &figure) }
        drawBrows(in: &figure)
        drawCheeks(in: &figure)
        drawEyes(in: &figure, center: CGPoint(x: 50, y: centerY - 3), scale: 1)
        drawMouth(in: &figure)
        if pose == .working { drawHeadphoneCups(in: &figure) }
        drawArms(in: &figure)
        drawProps(in: &figure)
        // Above the limbs, so an arm never hides where the time left ends.
        drawRingCap(in: &figure)
        drawEffectsFront(in: &figure)
    }

    // MARK: Ground

    private func drawGround(in context: inout GraphicsContext) {
        let width = pose == .done ? 28 - 6 * motion.hop : (pose == .onBreak ? 56 : 40)
        context.fill(Path(ellipseIn: CGRect(x: 50 - width / 2, y: ground, width: width, height: 5)),
                     with: .color(palette.shadow))
    }

    // MARK: Legs

    private func drawLegs(in context: inout GraphicsContext) {
        let hip = centerY + radius - 5
        var legs: [[CGPoint]]
        switch pose {
        case .waiting:
            legs = [[CGPoint(x: 43, y: hip), CGPoint(x: 41, y: 91)], [CGPoint(x: 57, y: hip), CGPoint(x: 64, y: 84)]]
        case .done:
            legs = [[CGPoint(x: 44, y: hip), CGPoint(x: 43, y: hip + 13)], [CGPoint(x: 56, y: hip), CGPoint(x: 57, y: hip + 13)]]
        case .onBreak:
            // Stretched out over the ground, crossed at the ankle.
            legs = [[CGPoint(x: 47, y: hip), CGPoint(x: 62, y: hip + 2), CGPoint(x: 76, y: 89)],
                    [CGPoint(x: 53, y: hip - 1), CGPoint(x: 66, y: hip - 1), CGPoint(x: 80, y: 86)]]
        case .ringing:
            legs = [[CGPoint(x: 42, y: hip), CGPoint(x: 38, y: 91)], [CGPoint(x: 58, y: hip), CGPoint(x: 62, y: 91)]]
        case .interrupted:
            legs = [[CGPoint(x: 45, y: hip), CGPoint(x: 45, y: 91)], [CGPoint(x: 55, y: hip), CGPoint(x: 55, y: 91)]]
        case .streak:
            legs = [[CGPoint(x: 42, y: hip), CGPoint(x: 36, y: 91)], [CGPoint(x: 58, y: hip), CGPoint(x: 64, y: 91)]]
        case .sleeping:
            legs = [[CGPoint(x: 43, y: hip), CGPoint(x: 28, y: 92)], [CGPoint(x: 57, y: hip), CGPoint(x: 72, y: 92)]]
        default:
            legs = [[CGPoint(x: 43, y: hip), CGPoint(x: 41, y: 91)], [CGPoint(x: 57, y: hip), CGPoint(x: 59, y: 91)]]
        }
        for (index, leg) in legs.enumerated() {
            context.stroke(polyline(leg), with: .color(palette.limbs),
                           style: StrokeStyle(lineWidth: legWidth, lineCap: .round, lineJoin: .round))
            guard let foot = leg.last else { continue }
            let outward: Double = pose == .onBreak ? 1 : (index == 0 ? -1 : 1)
            var shoe = context
            shoe.translateBy(x: foot.x + outward * 2, y: foot.y)
            // The tapping foot's toe is up.
            if pose == .waiting && index == 1 { shoe.rotate(by: .degrees(-25)) }
            if pose == .onBreak { shoe.rotate(by: .degrees(-60)) }
            shoe.fill(Path(ellipseIn: CGRect(x: -3.8, y: -2.6, width: 7.6, height: 5.2)), with: .color(palette.limbs))
        }
    }

    // MARK: Crown

    private var ringTop: Double { centerY - radius - rimWidth / 2 }

    private func drawCrown(in context: inout GraphicsContext) {
        let x = 50 + shift
        // The stem, then the big pressable button on it.
        // The stem is the ring's colour, so the crown never floats on a dark page.
        let stem = Path(roundedRect: CGRect(x: x - 3.5, y: ringTop - 6, width: 7, height: 8), cornerRadius: 1.2)
        context.fill(stem, with: .color(palette.ring))
        context.stroke(stem, with: .color(palette.eyes.opacity(0.85)), lineWidth: 1.2)
        let button = CGRect(x: x - 11, y: ringTop - 17, width: 22, height: 12)
        let shape = Path(roundedRect: button, cornerRadius: 4.5)
        context.fill(shape, with: .color(palette.crown))
        // A darker lip at the bottom, a highlight at the top: it presses.
        var lip = context
        lip.clip(to: shape)
        lip.fill(Path(CGRect(x: button.minX, y: button.maxY - 3.6, width: button.width, height: 3.6)),
                 with: .color(palette.eyes.opacity(0.22)))
        context.stroke(shape, with: .color(palette.eyes), lineWidth: 1.8)
        context.stroke(line(CGPoint(x: button.minX + 4.5, y: button.minY + 2.8),
                            CGPoint(x: button.minX + 10, y: button.minY + 2.8)),
                       with: .color(palette.face.opacity(0.7)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        if pose == .streak { drawStar(at: CGPoint(x: x, y: button.minY - 6), radius: 5.5, in: &context) }
    }

    // MARK: Ring and face

    private func drawRing(in context: inout GraphicsContext) {
        let face = circle(CGPoint(x: 50, y: centerY), radius)
        context.fill(face, with: .color(palette.face))
        // The track: a medium, muted terracotta, between the arc and the face,
        // so the whole round body shows on cream and on black.
        context.stroke(face, with: .color(palette.track), lineWidth: rimWidth)
        // Time left, clockwise from twelve. Done is all gold; ringing all bright.
        let left = ringLeft
        if pose == .done {
            // Brighter, lighter gold than the mustard crown.
            context.stroke(face, with: .color(palette.doneGold), lineWidth: rimWidth)
        } else if pose == .ringing {
            context.stroke(face, with: .color(palette.ringingRed), lineWidth: rimWidth)
        } else if left >= 0.999 {
            context.stroke(face, with: .color(palette.ring), lineWidth: rimWidth)
        } else if left > 0.005 {
            var arc = Path()
            arc.addArc(center: CGPoint(x: 50, y: centerY), radius: radius, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * left), clockwise: false)
            context.stroke(arc, with: .color(palette.ring), style: StrokeStyle(lineWidth: rimWidth, lineCap: .round))
        }
        // Dots at three and nine.
        for x in [50 - radius, 50 + radius] {
            context.fill(circle(CGPoint(x: x, y: centerY), 1.2), with: .color(palette.face))
        }
        // The outer edge: a clean circle, its ink a little heavier on one side when hand-made.
        let outer = circle(CGPoint(x: 50, y: centerY), radius + rimWidth / 2)
        context.stroke(outer, with: .color(palette.eyes.opacity(0.85)), lineWidth: 1.2)
        if handmade {
            for (from, to, width) in [(20.0, 150.0, 2.1), (200.0, 250.0, 1.7)] {
                var heavy = Path()
                heavy.addArc(center: CGPoint(x: 50, y: centerY), radius: radius + rimWidth / 2 + 0.3,
                             startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                context.stroke(heavy, with: .color(palette.eyes.opacity(0.85)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        if handmade { drawGrain(in: &context) }
    }

    /// A small bright cap where the time left ends, on a partly full ring.
    private func drawRingCap(in context: inout GraphicsContext) {
        let left = ringLeft
        guard pose != .done, pose != .ringing, left > 0.005, left < 0.999 else { return }
        let end = (-90 + 360 * left) * .pi / 180
        let tip = CGPoint(x: 50 + radius * cos(end), y: centerY + radius * sin(end))
        context.fill(circle(tip, rimWidth / 2 + 0.4), with: .color(palette.cap))
        context.fill(circle(CGPoint(x: tip.x - 0.8, y: tip.y - 0.8), 1), with: .color(palette.face.opacity(0.7)))
    }

    /// A faint paper grain on the face, the same every time.
    private func drawGrain(in context: inout GraphicsContext) {
        var seed: UInt64 = 0x7E57
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for _ in 0..<90 {
            let x = (next() * 2 - 1) * 23, y = (next() * 2 - 1) * 23
            guard x * x + y * y < 23 * 23 else { continue }
            context.fill(circle(CGPoint(x: 50 + x, y: centerY + y), 0.22 + next() * 0.18),
                         with: .color(palette.eyes.opacity(0.035)))
        }
    }

    /// The clock's one hand, worn as an eyebrow.
    private func drawBrowHand(in context: inout GraphicsContext) {
        let pivot = CGPoint(x: 50 + shift, y: centerY - 14.5)
        let angle = browAngle * .pi / 180
        let end = CGPoint(x: pivot.x + 8.5 * sin(angle), y: pivot.y - 8.5 * cos(angle))
        context.stroke(line(pivot, end), with: .color(palette.eyes),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        context.fill(circle(pivot, 1.8), with: .color(palette.eyes))
    }

    /// Small brows, only where the face needs them: kind and raised when
    /// interrupted, one cocked when waiting.
    private func drawBrows(in context: inout GraphicsContext) {
        let y = centerY - 11
        let style = StrokeStyle(lineWidth: 1.8, lineCap: .round)
        switch pose {
        case .interrupted:
            for side in [-1.0, 1.0] {
                let inner = CGPoint(x: 50 + side * 5.5, y: y - 1.6)
                let outer = CGPoint(x: 50 + side * 11.5, y: y + 0.8)
                context.stroke(line(inner, outer), with: .color(palette.eyes), style: style)
            }
        case .waiting:
            var brow = Path()
            brow.move(to: CGPoint(x: 54.5, y: y - 0.5))
            brow.addQuadCurve(to: CGPoint(x: 63.5, y: y + 0.5), control: CGPoint(x: 59, y: y - 4))
            context.stroke(brow, with: .color(palette.eyes), style: style)
        default:
            break
        }
    }

    private func drawCheeks(in context: inout GraphicsContext) {
        for x in [36.5, 63.5] {
            context.fill(Path(ellipseIn: CGRect(x: x - 2.4, y: centerY + 3.5, width: 4.8, height: 2.8)),
                         with: .color(palette.cheeks))
        }
    }

    /// Both eyes, around `center`, at `scale` (the glyph draws them larger).
    private func drawEyes(in context: inout GraphicsContext, center: CGPoint, scale s: Double) {
        let style = eyeStyle
        for side in [-1.0, 1.0] {
            let x = center.x + side * 8.5 * s
            var y = center.y
            let stroke = StrokeStyle(lineWidth: 2.4 * s, lineCap: .round)
            switch style {
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: x - 3.6 * s, y: y + 1.5 * s))
                arc.addQuadCurve(to: CGPoint(x: x + 3.6 * s, y: y + 1.5 * s), control: CGPoint(x: x, y: y - 4 * s))
                context.stroke(arc, with: .color(palette.eyes), style: stroke)
            case .sleepy, .closed:
                var arc = Path()
                let dip = style == .sleepy ? 3.4 : 1.6
                arc.move(to: CGPoint(x: x - 3.6 * s, y: y))
                arc.addQuadCurve(to: CGPoint(x: x + 3.6 * s, y: y), control: CGPoint(x: x, y: y + dip * s))
                context.stroke(arc, with: .color(palette.eyes), style: stroke)
            default:
                var width = 6.4, height = 8.8
                var lid: Double? = nil
                switch style {
                case .eager: width = 6.8; height = 9.4
                case .down: height = 6.4; y += 2.5 * s
                case .halfLid: lid = -0.32
                case .wide: width = 7.6; height = 10.8
                case .softDown: height = 8; y += 1 * s
                default: break
                }
                height = max(1.4, height * (1 - motion.blink)) * s
                width *= s
                let eye = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
                context.fill(Path(ellipseIn: eye), with: .color(palette.eyes))
                if lid == nil, height > 4.5 * s {
                    context.fill(circle(CGPoint(x: x + 1.3 * s, y: y - height / 2 + 2.2 * s), 1.1 * s),
                                 with: .color(palette.face))
                }
                if let lid {
                    // A heavy upper lid down to just past the middle.
                    let lidY = eye.midY + lid * height
                    context.fill(Path(CGRect(x: eye.minX - 0.6, y: eye.minY - 0.6, width: eye.width + 1.2,
                                             height: lidY - eye.minY + 0.6)),
                                 with: .color(palette.face))
                    context.stroke(line(CGPoint(x: eye.minX - 0.8 * s, y: lidY), CGPoint(x: eye.maxX + 0.8 * s, y: lidY)),
                                   with: .color(palette.eyes), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
                }
            }
        }
    }

    private func drawMouth(in context: inout GraphicsContext) {
        drawMouth(at: CGPoint(x: 50, y: centerY + 8), scale: 1, in: &context)
    }

    private func drawMouth(at m: CGPoint, scale s: Double, in context: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round)
        func p(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: m.x + dx * s, y: m.y + dy * s) }
        var mouth = Path()
        switch pose {
        case .ready:
            mouth.move(to: p(-5, 0)); mouth.addQuadCurve(to: p(5, 0), control: p(0, 5))
            context.stroke(mouth, with: .color(palette.eyes), style: stroke)
        case .onBreak:
            mouth.move(to: p(-4, 0.5)); mouth.addQuadCurve(to: p(4, 0.5), control: p(0, 4))
            context.stroke(mouth, with: .color(palette.eyes), style: stroke)
        case .streak:
            mouth.move(to: p(-6, -0.5)); mouth.addQuadCurve(to: p(6, -0.5), control: p(0, 6))
            context.stroke(mouth, with: .color(palette.eyes), style: stroke)
        case .working:
            mouth.move(to: p(-3.5, 1)); mouth.addLine(to: p(3, 1))
            context.stroke(mouth, with: .color(palette.eyes), style: stroke)
            // A small concentration tongue at the corner.
            context.fill(Path(ellipseIn: CGRect(x: m.x + 1.6 * s, y: m.y + 1.4 * s, width: 3.2 * s, height: 2.8 * s)),
                         with: .color(palette.effects))
        case .waiting:
            mouth.move(to: p(-3.8, 1.2)); mouth.addLine(to: p(3.8, 1.2))
            context.stroke(mouth, with: .color(palette.eyes), style: stroke)
        case .interrupted:
            // A small "oh well" smile.
            mouth.move(to: p(-3.5, 1)); mouth.addQuadCurve(to: p(3.5, 1), control: p(0, 3.2))
            context.stroke(mouth, with: .color(palette.eyes), style: stroke)
        case .done, .hello:
            let width = pose == .done ? 5.8 : 5
            mouth.move(to: p(-width, -0.5)); mouth.addQuadCurve(to: p(width, -0.5), control: p(0, pose == .done ? 9 : 8))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(palette.eyes))
        case .ringing:
            context.fill(Path(ellipseIn: CGRect(x: m.x - 2.4 * s, y: m.y - 1 * s, width: 4.8 * s, height: 6 * s)),
                         with: .color(palette.eyes))
        case .sleeping:
            context.fill(Path(ellipseIn: CGRect(x: m.x - 1.3 * s, y: m.y, width: 2.6 * s, height: 3 * s)),
                         with: .color(palette.eyes))
        }
    }

    // MARK: Headphones

    private func drawHeadphoneBand(in context: inout GraphicsContext) {
        var band = Path()
        band.addArc(center: CGPoint(x: 50, y: centerY), radius: radius + 7, startAngle: .degrees(-168),
                    endAngle: .degrees(-12), clockwise: false)
        context.stroke(band, with: .color(palette.crown), style: StrokeStyle(lineWidth: handmade ? 2 : 2.8, lineCap: .round))
    }

    private func drawHeadphoneCups(in context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let cup = CGRect(x: 50 + side * (radius + 1.5) - 5, y: centerY - 9.5, width: 10, height: 17)
            let shape = Path(roundedRect: cup, cornerRadius: 3.5)
            context.fill(shape, with: .color(palette.eyes))
            context.stroke(line(CGPoint(x: cup.midX - side * 2.2, y: cup.minY + 3), CGPoint(x: cup.midX - side * 2.2, y: cup.maxY - 3)),
                           with: .color(palette.crown), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    // MARK: Arms

    private func drawArms(in context: inout GraphicsContext) {
        let y = centerY
        let left = CGPoint(x: 50 - radius - 1, y: y + 5)
        let right = CGPoint(x: 50 + radius + 1, y: y + 5)
        // Each arm: shoulder, elbow, hand.
        let arms: [[CGPoint]]
        switch pose {
        case .ready:
            arms = [[left, CGPoint(x: 15, y: y + 14), CGPoint(x: 17, y: y + 24)],
                    [right, CGPoint(x: 88, y: y - 6), CGPoint(x: 67, y: y - 35)]]
        case .working:
            arms = [[left, CGPoint(x: 13, y: y + 16), CGPoint(x: 30, y: y + 28)],
                    [right, CGPoint(x: 87, y: y + 16), CGPoint(x: 70, y: y + 28)]]
        case .waiting:
            // Arms crossed over the lower face.
            arms = [[left, CGPoint(x: 6, y: y + 19), CGPoint(x: 61, y: y + 17)],
                    [right, CGPoint(x: 94, y: y + 19), CGPoint(x: 39, y: y + 19.5)]]
        case .done:
            arms = [[left, CGPoint(x: 15, y: y - 6), CGPoint(x: 12, y: y - 23)],
                    [right, CGPoint(x: 85, y: y - 6), CGPoint(x: 88, y: y - 23)]]
        case .onBreak:
            // Leaning back on one hand, the other holding the mug.
            arms = [[left, CGPoint(x: 15, y: y + 18), CGPoint(x: 18, y: y + 34)],
                    [right, CGPoint(x: 89, y: y + 6), CGPoint(x: 86, y: y - 6)]]
        case .ringing:
            arms = [[left, CGPoint(x: 12, y: y - 6), CGPoint(x: 36, y: y - 34)],
                    [right, CGPoint(x: 88, y: y - 6), CGPoint(x: 64, y: y - 34)]]
        case .hello:
            arms = [[left, CGPoint(x: 13, y: y - 9), CGPoint(x: 10, y: y - 31)],
                    [right, CGPoint(x: 85, y: y + 14), CGPoint(x: 83, y: y + 24)]]
        case .interrupted:
            // A kind "oh well" shrug, hands out and open.
            arms = [[left, CGPoint(x: 16, y: y + 16), CGPoint(x: 6, y: y + 6)],
                    [right, CGPoint(x: 84, y: y + 16), CGPoint(x: 94, y: y + 6)]]
        case .streak:
            // Hands on hips.
            arms = [[left, CGPoint(x: 11, y: y + 10), CGPoint(x: 24, y: y + 18)],
                    [right, CGPoint(x: 89, y: y + 10), CGPoint(x: 76, y: y + 18)]]
        case .sleeping:
            arms = [[left, CGPoint(x: 18, y: y + 14), CGPoint(x: 25, y: y + 24)],
                    [right, CGPoint(x: 82, y: y + 14), CGPoint(x: 75, y: y + 24)]]
        }
        for arm in arms {
            context.stroke(polyline(arm), with: .color(palette.limbs),
                           style: StrokeStyle(lineWidth: limbWidth, lineCap: .round, lineJoin: .round))
            if let hand = arm.last {
                context.fill(circle(hand, handmade ? 3 : 3.6), with: .color(palette.limbs))
            }
        }
    }

    // MARK: Props and effects

    private func drawProps(in context: inout GraphicsContext) {
        guard pose == .onBreak else { return }
        // A mug of something warm, steaming.
        let mug = CGRect(x: 83, y: centerY - 15, width: 12, height: 13)
        let body = Path(roundedRect: mug, cornerRadius: 2.4)
        context.fill(body, with: .color(palette.crown))
        context.stroke(body, with: .color(palette.eyes), lineWidth: 1.6)
        var handle = Path()
        handle.move(to: CGPoint(x: mug.minX, y: mug.minY + 3))
        handle.addQuadCurve(to: CGPoint(x: mug.minX, y: mug.maxY - 3), control: CGPoint(x: mug.minX - 6, y: mug.midY))
        context.stroke(handle, with: .color(palette.eyes), lineWidth: 1.6)
        context.fill(circle(CGPoint(x: 86, y: centerY - 6), handmade ? 3 : 3.6), with: .color(palette.limbs))
        let wisps = handmade ? [mug.minX + 2.5, mug.midX, mug.maxX - 2.5] : [mug.minX + 3.5, mug.maxX - 3.5]
        for (index, x) in wisps.enumerated() {
            let phase = (motion.steam + Double(index) / Double(wisps.count)).truncatingRemainder(dividingBy: 1)
            let moving = motion.steam != 0
            let base = mug.minY - 2 - (moving ? phase : 0.3) * 5
            var wisp = Path()
            wisp.move(to: CGPoint(x: x, y: base))
            wisp.addCurve(to: CGPoint(x: x, y: base - 10),
                          control1: CGPoint(x: x + 3, y: base - 3.5), control2: CGPoint(x: x - 3, y: base - 6.5))
            context.stroke(wisp, with: .color(palette.limbs.opacity(moving ? (1 - phase) * 0.85 : 0.75)),
                           style: StrokeStyle(lineWidth: handmade ? 1.6 : 2.2, lineCap: .round))
        }
    }

    private func drawEffectsBehind(in context: inout GraphicsContext) {
        guard pose == .ringing else { return }
        // Shaking: vibration lines round the whole body.
        for (start, end) in [(-20.0, 20.0), (160.0, 200.0)] {
            for r in [radius + 9, radius + 13.5] {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 50, y: centerY), radius: r, startAngle: .degrees(start),
                           endAngle: .degrees(end), clockwise: false)
                context.stroke(arc, with: .color(palette.effects), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func drawEffectsFront(in context: inout GraphicsContext) {
        let y = centerY
        switch pose {
        case .ringing:
            // The alarm lines, fanning out from the crown: only here.
            let center = CGPoint(x: 50 + shift, y: ringTop - 11)
            for side in [-1.0, 1.0] {
                for degrees in [-32.0, 0, 32] {
                    let a = degrees * .pi / 180
                    let dx = cos(a) * side, dy = sin(a)
                    context.stroke(line(CGPoint(x: center.x + dx * 14, y: center.y + dy * 14),
                                        CGPoint(x: center.x + dx * 20, y: center.y + dy * 20)),
                                   with: .color(palette.effects), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            }
        case .done:
            let sparkles: [(CGPoint, Double, Bool)] = handmade
                ? [(CGPoint(x: 18, y: y - 34), 5, true), (CGPoint(x: 84, y: y - 38), 4, false),
                   (CGPoint(x: 9, y: y + 4), 3, false), (CGPoint(x: 92, y: y + 2), 3.6, true),
                   (CGPoint(x: 76, y: y - 52), 2.6, true)]
                : [(CGPoint(x: 18, y: y - 34), 5.5, true), (CGPoint(x: 86, y: y - 36), 5, false)]
            for (point, size, gold) in sparkles {
                context.fill(sparkle(at: point, radius: size), with: .color(gold ? palette.crown : palette.effects))
            }
            if handmade {
                // A little confetti.
                for (point, angle, gold) in [(CGPoint(x: 28, y: y - 46), 30.0, false), (CGPoint(x: 70, y: y - 46), -25, true),
                                             (CGPoint(x: 6, y: y - 16), 60, true), (CGPoint(x: 95, y: y - 18), -50, false)] {
                    var piece = context
                    piece.translateBy(x: point.x, y: point.y)
                    piece.rotate(by: .degrees(angle))
                    piece.fill(Path(roundedRect: CGRect(x: -2.2, y: -1, width: 4.4, height: 2), cornerRadius: 0.6),
                               with: .color(gold ? palette.crown : palette.effects))
                }
            }
        case .hello:
            // A curved motion line by the waving hand.
            for r in [7.0, 10.5] {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 10, y: y - 31), radius: r, startAngle: .degrees(195),
                           endAngle: .degrees(255), clockwise: false)
                context.stroke(arc, with: .color(palette.limbs.opacity(0.6)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        case .waiting:
            // The tapping foot.
            for r in [6.0, 9.0] {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 66, y: 84), radius: r, startAngle: .degrees(-70),
                           endAngle: .degrees(-20), clockwise: false)
                context.stroke(arc, with: .color(palette.limbs.opacity(0.6)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        case .sleeping:
            for (origin, size) in [(CGPoint(x: 70, y: y - 40), 6.0), (CGPoint(x: 80, y: y - 50), 4.5)] {
                var z = Path()
                z.move(to: origin)
                z.addLine(to: CGPoint(x: origin.x + size, y: origin.y))
                z.addLine(to: CGPoint(x: origin.x, y: origin.y + size))
                z.addLine(to: CGPoint(x: origin.x + size, y: origin.y + size))
                context.stroke(z, with: .color(palette.limbs), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        default:
            break
        }
    }

    // MARK: Glyph

    /// Under 40 pt: just the head. The ring, the crown and two eyes that
    /// still show the mood, and a mouth when there's room.
    private func drawGlyph(mouth: Bool, in context: inout GraphicsContext) {
        guard mouth else { return drawTinyGlyph(in: &context) }
        let c = CGPoint(x: 50, y: 58)
        let r = 32.0, rim = 10.0
        let top = c.y - r - rim / 2
        context.fill(Path(roundedRect: CGRect(x: 45.5, y: top - 7, width: 9, height: 9), cornerRadius: 1.5),
                     with: .color(palette.ring))
        let button = Path(roundedRect: CGRect(x: 35, y: top - 20, width: 30, height: 15), cornerRadius: 6)
        context.fill(button, with: .color(palette.crown))
        context.stroke(button, with: .color(palette.eyes), lineWidth: 3)
        let face = circle(c, r)
        context.fill(face, with: .color(palette.face))
        context.stroke(face, with: .color(palette.track), lineWidth: rim)
        let left = ringLeft
        if pose == .done {
            context.stroke(face, with: .color(palette.doneGold), lineWidth: rim)
        } else if pose == .ringing {
            context.stroke(face, with: .color(palette.ringingRed), lineWidth: rim)
        } else if left >= 0.999 {
            context.stroke(face, with: .color(palette.ring), lineWidth: rim)
        } else if left > 0.005 {
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * left), clockwise: false)
            context.stroke(arc, with: .color(palette.ring), style: StrokeStyle(lineWidth: rim, lineCap: .round))
        }
        context.stroke(circle(c, r + rim / 2), with: .color(palette.eyes), lineWidth: 2.4)
        var eyes = context
        eyes.translateBy(x: 0, y: -3)
        drawEyes(in: &eyes, center: CGPoint(x: c.x, y: c.y - 3), scale: 1.45)
        drawMouth(at: CGPoint(x: c.x, y: c.y + 10), scale: 1.4, in: &context)
    }

    /// The smallest Tick (16 px): solid shapes only, filling the square:
    /// a terracotta ring, a mustard crown and two dark eyes.
    private func drawTinyGlyph(in context: inout GraphicsContext) {
        let c = CGPoint(x: 50, y: 55)
        let outer = 40.0, inner = 26.0
        context.fill(Path(CGRect(x: 43, y: c.y - outer - 5, width: 14, height: 7)), with: .color(palette.ring))
        context.fill(Path(roundedRect: CGRect(x: 30, y: 4, width: 40, height: 9), cornerRadius: 3),
                     with: .color(palette.crown))
        context.fill(circle(c, outer), with: .color(palette.ring))
        context.fill(circle(c, inner), with: .color(palette.face))
        for side in [-1.0, 1.0] {
            context.fill(circle(CGPoint(x: c.x + side * 10, y: c.y - 2), 5.5), with: .color(palette.eyes))
        }
    }

    // MARK: Helpers

    private func circle(_ center: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 3 {
            path.addQuadCurve(to: points[2], control: points[1])
        } else {
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
        return path
    }

    private func sparkle(at c: CGPoint, radius r: Double) -> Path {
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4
            let length = i.isMultiple(of: 2) ? r : r * 0.32
            let point = CGPoint(x: c.x + length * sin(angle), y: c.y - length * cos(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func drawStar(at c: CGPoint, radius r: Double, in context: inout GraphicsContext) {
        var star = Path()
        for i in 0..<10 {
            let angle = Double(i) * .pi / 5
            let length = i.isMultiple(of: 2) ? r : r * 0.45
            let point = CGPoint(x: c.x + length * sin(angle), y: c.y - length * cos(angle))
            i == 0 ? star.move(to: point) : star.addLine(to: point)
        }
        star.closeSubpath()
        context.fill(star, with: .color(palette.effects))
        context.stroke(star, with: .color(palette.eyes), lineWidth: 1.2)
    }
}
