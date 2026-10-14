import SwiftUI

/// The soft shadow under Tick, on the ground: it shrinks as Tick hops.
struct TickGroundPart: View {
    let look: TickLook

    var body: some View {
        let width = look.rig.shadowWidth - 6 * look.motion.hop
        Ink(Path(ellipseIn: CGRect(x: 50 - width / 2, y: TickLook.ground, width: width, height: 5)))
            .fill(look.palette.shadow)
    }
}

/// The legs and feet, behind the body.
struct TickLegsPart: View {
    let look: TickLook

    var body: some View {
        let rig = look.rig
        let style = StrokeStyle(lineWidth: look.legWidth, lineCap: .round, lineJoin: .round)
        ZStack {
            ForEach(Array([(rig.leftLeg, rig.leftFoot), (rig.rightLeg, rig.rightFoot)].enumerated()), id: \.offset) { _, leg in
                Ink(TickPath.limb(leg.0, from: look)).stroke(look.palette.limbs, style: style)
                foot(leg.0, tilt: leg.1)
            }
        }
    }

    private func foot(_ leg: TickRig.Limb, tilt: Double) -> some View {
        let end = look.body(leg.end)
        // The shoe points away from the body.
        let outward: Double = leg.end.x < 0 ? -1 : 1
        let shoe = Path(ellipseIn: CGRect(x: -3.8, y: -2.6, width: 7.6, height: 5.2))
            .applying(CGAffineTransform(rotationAngle: tilt * .pi / 180))
            .applying(CGAffineTransform(translationX: end.x + outward * 2, y: end.y))
        return Ink(shoe).fill(look.palette.limbs)
    }
}

/// The face, the muted track, and the whole-ring colours (gold when done,
/// red when ringing).
struct TickRingTrackPart: View {
    let look: TickLook

    var body: some View {
        let face = TickPath.circle(look.center, look.radius)
        ZStack {
            Ink(face).fill(look.palette.face)
            Ink(face).stroke(look.palette.track, lineWidth: look.rimWidth)
            Ink(face).stroke(look.palette.doneGold, lineWidth: look.rimWidth).opacity(look.rig.gold)
            Ink(face).stroke(look.palette.ringingRed, lineWidth: look.rimWidth).opacity(look.rig.alarm)
        }
    }
}

/// The time left: a bright arc clockwise from twelve.
struct TickRingArcPart: View {
    let look: TickLook

    var body: some View {
        let left = min(1, max(0, look.progress))
        Group {
            if left >= 0.999 {
                Ink(TickPath.circle(look.center, look.radius)).stroke(look.palette.ring, lineWidth: look.rimWidth)
            } else if left > 0.005 {
                Ink(TickPath.arc(look.center, look.radius, from: -90, to: -90 + 360 * left))
                    .stroke(look.palette.ring, style: StrokeStyle(lineWidth: look.rimWidth, lineCap: .round))
            }
        }
        .opacity(look.arcOpacity)
    }
}

/// The ring's edge: dots at three and nine, the outline (heavier on one
/// side when hand-made), and a faint grain on the face.
struct TickRingRimPart: View {
    let look: TickLook

    var body: some View {
        let ink = look.palette.eyes.opacity(0.85)
        ZStack {
            Ink(dots).fill(look.palette.face)
            Ink(TickPath.circle(look.center, look.radius + look.rimWidth / 2)).stroke(ink, lineWidth: 1.2)
            if look.handmade {
                ForEach(Array([(20.0, 150.0, 2.1), (200.0, 250.0, 1.7)].enumerated()), id: \.offset) { _, heavy in
                    Ink(TickPath.arc(look.center, look.radius + look.rimWidth / 2 + 0.3, from: heavy.0, to: heavy.1))
                        .stroke(ink, style: StrokeStyle(lineWidth: heavy.2, lineCap: .round))
                }
                Ink(grain).fill(look.palette.eyes.opacity(0.035))
            }
        }
    }

    private var dots: Path {
        var path = Path()
        for x in [50 - look.radius, 50 + look.radius] {
            path.addPath(TickPath.circle(CGPoint(x: x, y: look.centerY), 1.2))
        }
        return path
    }

    /// The same speckle every time.
    private var grain: Path {
        var seed: UInt64 = 0x7E57
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        var path = Path()
        for _ in 0..<90 {
            let x = (next() * 2 - 1) * 23, y = (next() * 2 - 1) * 23
            let size = 0.22 + next() * 0.18
            guard x * x + y * y < 23 * 23 else { continue }
            path.addPath(TickPath.circle(CGPoint(x: 50 + x, y: look.centerY + y), size))
        }
        return path
    }
}

/// The arms and hands, in front of the face.
struct TickArmsPart: View {
    let look: TickLook

    var body: some View {
        let style = StrokeStyle(lineWidth: look.limbWidth, lineCap: .round, lineJoin: .round)
        ZStack {
            ForEach(Array([look.rig.leftArm, look.rig.rightArm].enumerated()), id: \.offset) { _, arm in
                Ink(TickPath.limb(arm, from: look)).stroke(look.palette.limbs, style: style)
                Ink(TickPath.circle(look.body(arm.end), look.handRadius)).fill(look.palette.limbs)
            }
        }
    }
}

/// The bright round end of the time left, above the arms so a hand never
/// hides where the time ends.
struct TickRingCapPart: View {
    let look: TickLook

    var body: some View {
        let left = look.progress
        if left > 0.005, left < 0.999 {
            let end = (-90 + 360 * left) * .pi / 180
            let tip = CGPoint(x: 50 + look.radius * cos(end), y: look.centerY + look.radius * sin(end))
            ZStack {
                Ink(TickPath.circle(tip, look.rimWidth / 2 + 0.4)).fill(look.palette.cap)
                Ink(TickPath.circle(CGPoint(x: tip.x - 0.8, y: tip.y - 0.8), 1)).fill(look.palette.face.opacity(0.7))
            }
            .opacity(look.arcOpacity)
        }
    }
}

/// The crown: a stem from the ring and the big button on it, which
/// presses in.
struct TickCrownPart: View {
    let look: TickLook

    var body: some View {
        let x = 50 + look.shift
        let ringTop = look.ringTop
        // The stem is the ring's colour, so the crown never floats on a dark page.
        let stem = Path(roundedRect: CGRect(x: x - 3.5, y: ringTop - 6, width: 7, height: 6.6), cornerRadius: 1.2)
        let press = 2.5 * look.rig.crownPress
        let button = CGRect(x: x - 11, y: ringTop - 17 + press, width: 22, height: 12)
        let shape = Path(roundedRect: button, cornerRadius: 4.5)
        ZStack {
            Ink(stem).fill(look.palette.ring)
            Ink(stem).stroke(look.palette.eyes.opacity(0.85), lineWidth: 1.2)
            Ink(shape).fill(look.palette.crown)
            // A darker lip at the bottom, a highlight at the top: it presses.
            Ink(Path(CGRect(x: button.minX, y: button.maxY - 3.6, width: button.width, height: 3.6)))
                .fill(look.palette.eyes.opacity(0.22))
                .clipShape(Ink(shape))
            Ink(shape).stroke(look.palette.eyes, lineWidth: 1.8)
            Ink(TickPath.line(CGPoint(x: button.minX + 4.5, y: button.minY + 2.8),
                              CGPoint(x: button.minX + 10, y: button.minY + 2.8)))
                .stroke(look.palette.face.opacity(0.7), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }
}
