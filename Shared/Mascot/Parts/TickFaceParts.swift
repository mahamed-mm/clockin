import SwiftUI

/// Small blush cheeks.
struct TickCheeksPart: View {
    let look: TickLook

    var body: some View {
        var path = Path(), flushed = Path()
        let shift = 0.6 * look.face.gazeX
        for x in [36.5 + shift, 63.5 + shift] {
            path.addEllipse(in: CGRect(x: x - 2.4, y: look.centerY + 3.5, width: 4.8, height: 2.8))
            // Redder and a little wider with effort.
            flushed.addEllipse(in: CGRect(x: x - 3.2, y: look.centerY + 3.1, width: 6.4, height: 3.6))
        }
        return ZStack {
            Ink(path).fill(look.palette.cheeks).opacity(look.face.cheeks)
            Ink(flushed).fill(look.palette.cheeks).opacity(min(1, 1.6 * look.face.flush))
        }
    }
}

/// Both eyes, around `center`, at `scale` (the glyph draws them larger).
struct TickEyesPart: View {
    let look: TickLook
    var center: CGPoint
    var scale: Double = 1

    var body: some View {
        let eyes = TickEyeShapes(style: look.face.eyes, blink: look.face.blink, center: center, scale: scale)
        ZStack {
            Ink(eyes.strokes).stroke(look.palette.eyes, style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
            Ink(eyes.fills).fill(look.palette.eyes)
            Ink(eyes.highlights).fill(look.palette.face)
            Ink(eyes.lids).fill(look.palette.face)
            Ink(eyes.lidLines).stroke(look.palette.eyes, style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        }
    }
}

/// The eyes' paths for one style, split by how each is painted.
struct TickEyeShapes {
    var strokes = Path(), fills = Path(), highlights = Path(), lids = Path(), lidLines = Path()

    init(style: TickFace.Eyes, blink: Double, center: CGPoint, scale s: Double) {
        for side in [-1.0, 1.0] {
            let x = center.x + side * 8.5 * s
            var y = center.y
            switch style {
            case .happy:
                strokes.move(to: CGPoint(x: x - 3.6 * s, y: y + 1.5 * s))
                strokes.addQuadCurve(to: CGPoint(x: x + 3.6 * s, y: y + 1.5 * s), control: CGPoint(x: x, y: y - 4 * s))
            case .sleepy, .closed:
                let dip = style == .sleepy ? 3.4 : 1.6
                strokes.move(to: CGPoint(x: x - 3.6 * s, y: y))
                strokes.addQuadCurve(to: CGPoint(x: x + 3.6 * s, y: y), control: CGPoint(x: x, y: y + dip * s))
            case .squeezed:
                // > <: each points in toward the nose.
                strokes.move(to: CGPoint(x: x + side * 3 * s, y: y - 3 * s))
                strokes.addLine(to: CGPoint(x: x - side * 2.6 * s, y: y))
                strokes.addLine(to: CGPoint(x: x + side * 3 * s, y: y + 3 * s))
            case .squint where side < 0:
                // The near eye screwed up, a little higher at the outside.
                strokes.move(to: CGPoint(x: x - 3.6 * s, y: y - 1.2 * s))
                strokes.addQuadCurve(to: CGPoint(x: x + 3.4 * s, y: y + 0.6 * s), control: CGPoint(x: x, y: y - 1.8 * s))
            default:
                var width = 6.4, height = 8.8
                var lid: Double? = nil
                switch style {
                case .eager: width = 6.8; height = 9.4
                case .down: height = 6.4; y += 2.5 * s
                case .halfLid: lid = -0.32
                case .tired: lid = 0.02; height = 8; y += 0.6 * s
                case .wide: width = 7.6; height = 10.8
                case .softDown: height = 8; y += 1 * s
                default: break
                }
                height = max(1.4, height * (1 - blink)) * s
                width *= s
                let eye = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
                fills.addEllipse(in: eye)
                if lid == nil, height > 4.5 * s {
                    highlights.addPath(TickPath.circle(CGPoint(x: x + 1.3 * s, y: y - height / 2 + 2.2 * s), 1.1 * s))
                }
                if let lid {
                    // A heavy upper lid down to just past the middle.
                    let lidY = eye.midY + lid * height
                    lids.addRect(CGRect(x: eye.minX - 0.6, y: eye.minY - 0.6, width: eye.width + 1.2,
                                        height: lidY - eye.minY + 0.6))
                    lidLines.addPath(TickPath.line(CGPoint(x: eye.minX - 0.8 * s, y: lidY),
                                                   CGPoint(x: eye.maxX + 0.8 * s, y: lidY)))
                }
            }
        }
    }
}

/// The mouth, at `center` and `scale`.
struct TickMouthPart: View {
    let look: TickLook
    var center: CGPoint
    var scale: Double = 1

    var body: some View {
        let m = center, s = scale
        func p(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: m.x + dx * s, y: m.y + dy * s) }
        let stroke = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round)
        var line = Path(), solid = Path(), tongue = Path(), teeth = Path(), grit = Path()
        switch look.face.mouth {
        case .smile: line.move(to: p(-5, 0)); line.addQuadCurve(to: p(5, 0), control: p(0, 5))
        case .content: line.move(to: p(-4, 0.5)); line.addQuadCurve(to: p(4, 0.5), control: p(0, 4))
        case .proud: line.move(to: p(-6, -0.5)); line.addQuadCurve(to: p(6, -0.5), control: p(0, 6))
        case .focused:
            line.move(to: p(-3.5, 1)); line.addLine(to: p(3, 1))
            // A small concentration tongue at the corner.
            tongue.addEllipse(in: CGRect(x: m.x + 1.6 * s, y: m.y + 1.4 * s, width: 3.2 * s, height: 2.8 * s))
        case .flat: line.move(to: p(-3.8, 1.2)); line.addLine(to: p(3.8, 1.2))
        case .kind: line.move(to: p(-3.5, 1)); line.addQuadCurve(to: p(3.5, 1), control: p(0, 3.2))
        case .openSmile, .bigOpenSmile:
            let big = look.face.mouth == .bigOpenSmile
            let width = big ? 5.8 : 5
            solid.move(to: p(-width, -0.5)); solid.addQuadCurve(to: p(width, -0.5), control: p(0, big ? 9 : 8))
            solid.closeSubpath()
        case .oh: solid.addEllipse(in: CGRect(x: m.x - 2.4 * s, y: m.y - 1 * s, width: 4.8 * s, height: 6 * s))
        case .snore: solid.addEllipse(in: CGRect(x: m.x - 1.3 * s, y: m.y, width: 2.6 * s, height: 3 * s))
        case .set: line.move(to: p(-4.2, 2)); line.addQuadCurve(to: p(4.2, 2), control: p(0, 0.2))
        case .gritted:
            // Clenched teeth: a rounded slot with a line across.
            let slot = CGRect(x: m.x - 5 * s, y: m.y - 1 * s, width: 10 * s, height: 5.6 * s)
            teeth.addRoundedRect(in: slot, cornerSize: CGSize(width: 2 * s, height: 2 * s))
            grit.addRoundedRect(in: slot, cornerSize: CGSize(width: 2 * s, height: 2 * s))
            grit.move(to: p(-5, 1.8)); grit.addLine(to: p(5, 1.8))
            grit.move(to: p(-1.7, -1)); grit.addLine(to: p(-1.7, 4.6))
            grit.move(to: p(1.7, -1)); grit.addLine(to: p(1.7, 4.6))
        case .puffed: solid.addEllipse(in: CGRect(x: m.x - 1.8 * s, y: m.y + 0.4 * s, width: 3.6 * s, height: 2.4 * s))
        case .pant:
            let open = min(1, max(0, look.face.mouthOpen))
            let height = (3.2 + 5.2 * open) * s
            solid.addEllipse(in: CGRect(x: m.x - 4.2 * s, y: m.y - 1.2 * s, width: 8.4 * s, height: height))
            // The tongue hangs out over the lower lip.
            tongue.addEllipse(in: CGRect(x: m.x - 0.6 * s, y: m.y - 1.2 * s + height - 2.4 * s, width: 4.6 * s, height: 4.2 * s))
        }
        return ZStack {
            Ink(teeth).fill(look.palette.face)
            Ink(grit).stroke(look.palette.eyes, style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
            Ink(line).stroke(look.palette.eyes, style: stroke)
            Ink(solid).fill(look.palette.eyes)
            Ink(tongue).fill(look.palette.effects)
        }
    }
}

/// Plain brows, only where the face needs them: kind and raised when
/// interrupted, one cocked when waiting.
struct TickBrowsPart: View {
    let look: TickLook

    var body: some View {
        let y = look.centerY - 11 - look.motion.browLift
        let g = look.face.gazeX
        var path = Path()
        switch look.face.brows {
        case .innerRaised:
            for side in [-1.0, 1.0] {
                path.addPath(TickPath.line(CGPoint(x: 50 + g + side * 5.5, y: y - 1.6), CGPoint(x: 50 + g + side * 11.5, y: y + 0.8)))
            }
        case .singleRaised:
            path.move(to: CGPoint(x: 54.5 + g, y: y - 0.5))
            path.addQuadCurve(to: CGPoint(x: 63.5 + g, y: y + 0.5), control: CGPoint(x: 59 + g, y: y - 4))
        case .none:
            break
        }
        return Ink(path).stroke(look.palette.eyes, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }
}

/// The clock's one hand, worn as an eyebrow.
struct TickBrowHandPart: View {
    let look: TickLook

    var body: some View {
        let pivot = CGPoint(x: 50 + look.shift, y: look.centerY - 14.5)
        let angle = (look.face.browHandAngle + 8 * look.motion.tremble) * .pi / 180
        let end = CGPoint(x: pivot.x + 8.5 * sin(angle), y: pivot.y - 8.5 * cos(angle))
        return ZStack {
            Ink(TickPath.line(pivot, end)).stroke(look.palette.eyes, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Ink(TickPath.circle(pivot, 1.8)).fill(look.palette.eyes)
        }
        .opacity(look.face.browHand)
    }
}
