import SwiftUI

/// What sits behind the body: the headphones' band over the head, and the
/// alarm's vibration lines round it.
struct TickBackPropsPart: View {
    let look: TickLook

    var body: some View {
        ZStack {
            Ink(TickPath.arc(look.center, look.radius + 7, from: -168, to: -12))
                .stroke(look.palette.crown, style: StrokeStyle(lineWidth: look.handmade ? 2 : 2.8, lineCap: .round))
                .opacity(look.rig.headphones)
                .offset(y: -14 * look.motion.headphonesAbove)
            Ink(vibration)
                .stroke(look.palette.effects, style: StrokeStyle(lineWidth: look.handmade ? 2 : 3, lineCap: .round))
                .opacity(look.rig.alarm * (1 - 0.6 * look.motion.alarmFlash))
        }
    }

    private var vibration: Path {
        var path = Path()
        // One bold line a side when small, two fine ones when large.
        let radii = look.handmade ? [look.radius + 9, look.radius + 13.5] : [look.radius + 10]
        for (start, end) in [(-20.0, 20.0), (160.0, 200.0)] {
            for r in radii {
                path.addPath(TickPath.arc(look.center, r, from: start, to: end))
            }
        }
        return path
    }
}

/// The headphones' cups, over the ears.
struct TickHeadphoneCupsPart: View {
    let look: TickLook

    var body: some View {
        var cups = Path(), stripes = Path()
        for side in [-1.0, 1.0] {
            let cup = CGRect(x: 50 + side * (look.radius + 1.5) - 5, y: look.centerY - 9.5, width: 10, height: 17)
            cups.addRoundedRect(in: cup, cornerSize: CGSize(width: 3.5, height: 3.5))
            stripes.addPath(TickPath.line(CGPoint(x: cup.midX - side * 2.2, y: cup.minY + 3),
                                          CGPoint(x: cup.midX - side * 2.2, y: cup.maxY - 3)))
        }
        return ZStack {
            Ink(cups).fill(look.palette.eyes)
            Ink(stripes).stroke(look.palette.crown, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .opacity(look.rig.headphones)
        .offset(y: -14 * look.motion.headphonesAbove)
    }
}

/// A mug of something warm, steaming, in the right hand.
struct TickMugPart: View {
    let look: TickLook

    var body: some View {
        let mug = CGRect(x: 83, y: look.centerY - 15, width: 12, height: 13)
        let body = Path(roundedRect: mug, cornerRadius: 2.4)
        var handle = Path()
        handle.move(to: CGPoint(x: mug.minX, y: mug.minY + 3))
        handle.addQuadCurve(to: CGPoint(x: mug.minX, y: mug.maxY - 3), control: CGPoint(x: mug.minX - 6, y: mug.midY))
        return ZStack {
            Ink(body).fill(look.palette.crown)
            Ink(body).stroke(look.palette.eyes, lineWidth: 1.6)
            Ink(handle).stroke(look.palette.eyes, lineWidth: 1.6)
            Ink(TickPath.circle(CGPoint(x: 86, y: look.centerY - 6), look.handRadius)).fill(look.palette.limbs)
            steam(above: mug)
        }
        .scaleEffect(1 - look.motion.mugIn, anchor: UnitPoint(x: 0.86, y: (look.centerY - 6) / 100))
        .opacity(look.rig.mug)
    }

    private func steam(above mug: CGRect) -> some View {
        let wisps = look.handmade ? [mug.minX + 2.5, mug.midX, mug.maxX - 2.5] : [mug.minX + 3.5, mug.maxX - 3.5]
        let moving = look.motion.steam != 0
        return ZStack {
            ForEach(Array(wisps.enumerated()), id: \.offset) { index, x in
                let phase = (look.motion.steam + Double(index) / Double(wisps.count)).truncatingRemainder(dividingBy: 1)
                let base = mug.minY - 2 - (moving ? phase : 0.3) * 5
                Ink(wisp(x: x, base: base))
                    .stroke(look.palette.limbs.opacity(moving ? (1 - phase) * 0.85 : 0.75),
                            style: StrokeStyle(lineWidth: look.handmade ? 1.6 : 2.2, lineCap: .round))
            }
        }
    }

    private func wisp(x: Double, base: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: base))
        path.addCurve(to: CGPoint(x: x, y: base - 10),
                      control1: CGPoint(x: x + 3, y: base - 3.5), control2: CGPoint(x: x - 3, y: base - 6.5))
        return path
    }
}

/// The effects in front: alarm lines, sparkles, the wave and the tapping
/// foot's lines, z's, and the star on the crown.
struct TickEffectsPart: View {
    let look: TickLook

    var body: some View {
        let rig = look.rig
        ZStack {
            Ink(alarmLines).stroke(look.palette.effects, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .opacity(rig.alarm * (1 - 0.6 * look.motion.alarmFlash))
            sparkles
                .scaleEffect(1 - 0.7 * look.motion.sparklesIn, anchor: UnitPoint(x: 0.5, y: look.centerY / 100))
                .opacity(rig.sparkles * (1 - look.motion.sparklesIn))
            if look.showsMotionLines {
                Ink(waveLines).stroke(look.palette.limbs.opacity(0.6), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .opacity(rig.waveLines)
                Ink(tapLines).stroke(look.palette.limbs.opacity(0.6), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .opacity(rig.tapLines)
            }
            Ink(zees).stroke(look.palette.limbs, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .opacity(rig.zees * (1 - look.motion.zeeRise))
                .offset(x: 3 * look.motion.zeeRise, y: -8 * look.motion.zeeRise)
            star
                .offset(y: -16 * look.motion.starAbove)
                .opacity(rig.star * (1 - look.motion.starAbove))
            if look.motion.puff > 0 {
                puff
            }
            if look.motion.impact > 0 {
                Ink(impactLines)
                    .stroke(look.palette.limbs.opacity(0.75),
                            style: StrokeStyle(lineWidth: look.handmade ? 1.8 : 2.4, lineCap: .round))
                    .opacity(look.motion.impact)
            }
        }
    }

    /// A little cloud of breath drifting off the mouth, up and away to the
    /// right, fading as it goes.
    private var puff: some View {
        let p = look.motion.puff
        let mouth = CGPoint(x: 50 + look.face.gazeX + 7 + 7 * p, y: look.centerY + 7 - 3 * p)
        let sizes = look.handmade ? [(0.0, 0.0, 2.2), (3.0, -1.6, 1.6), (5.2, -3.4, 1.1)] : [(0.0, 0.0, 2.8), (4.0, -2.4, 2)]
        var cloud = Path()
        for (dx, dy, r) in sizes { cloud.addPath(TickPath.circle(CGPoint(x: mouth.x + dx, y: mouth.y + dy), r * (0.6 + 0.6 * p))) }
        return Ink(cloud)
            .stroke(look.palette.eyes.opacity(0.45), lineWidth: look.handmade ? 1.2 : 1.6)
            .opacity(sin(.pi * p))
    }

    /// A burst of short lines fanning out round where a punch or kick lands,
    /// away from the body: four when there's room, two bolder ones when small.
    private var impactLines: Path {
        let at = look.motion.impactAt
        let hit = look.body(at)
        let away = atan2(at.y, at.x)
        let spread = look.handmade ? [-1.3, -0.7, 0.7, 1.3] : [-0.75, 0.75]
        let start = 8.5 + 1.5 * (1 - look.motion.impact), length = look.handmade ? 4.5 : 5
        var path = Path()
        for offset in spread {
            let a = away + offset
            path.addPath(TickPath.line(CGPoint(x: hit.x + start * cos(a), y: hit.y + start * sin(a)),
                                       CGPoint(x: hit.x + (start + length) * cos(a), y: hit.y + (start + length) * sin(a))))
        }
        return path
    }

    /// Fanning out from the crown.
    private var alarmLines: Path {
        let center = CGPoint(x: 50 + look.shift, y: look.ringTop - 11)
        var path = Path()
        for side in [-1.0, 1.0] {
            for degrees in [-32.0, 0, 32] {
                let a = degrees * .pi / 180
                let dx = cos(a) * side, dy = sin(a)
                path.addPath(TickPath.line(CGPoint(x: center.x + dx * 14, y: center.y + dy * 14),
                                           CGPoint(x: center.x + dx * 20, y: center.y + dy * 20)))
            }
        }
        return path
    }

    private var sparkles: some View {
        let y = look.centerY
        let stars: [(CGPoint, Double, Bool)] = look.handmade
            ? [(CGPoint(x: 18, y: y - 34), 5, true), (CGPoint(x: 84, y: y - 38), 4, false),
               (CGPoint(x: 9, y: y + 4), 3, false), (CGPoint(x: 92, y: y + 2), 3.6, true),
               (CGPoint(x: 76, y: y - 52), 2.6, true)]
            : [(CGPoint(x: 18, y: y - 34), 5.5, true), (CGPoint(x: 86, y: y - 36), 5, false)]
        var gold = Path(), bright = Path()
        for (point, size, isGold) in stars {
            isGold ? gold.addPath(TickPath.sparkle(at: point, radius: size)) : bright.addPath(TickPath.sparkle(at: point, radius: size))
        }
        if look.handmade {
            // A little confetti.
            for (point, angle, isGold) in [(CGPoint(x: 28, y: y - 46), 30.0, false), (CGPoint(x: 70, y: y - 46), -25, true),
                                           (CGPoint(x: 6, y: y - 16), 60, true), (CGPoint(x: 95, y: y - 18), -50, false)] {
                let piece = Path(roundedRect: CGRect(x: -2.2, y: -1, width: 4.4, height: 2), cornerRadius: 0.6)
                    .applying(CGAffineTransform(rotationAngle: angle * .pi / 180))
                    .applying(CGAffineTransform(translationX: point.x, y: point.y))
                isGold ? gold.addPath(piece) : bright.addPath(piece)
            }
        }
        return ZStack {
            Ink(gold).fill(look.palette.crown)
            Ink(bright).fill(look.palette.effects)
        }
    }

    /// A curved motion line by the waving hand.
    private var waveLines: Path {
        let hand = look.body(look.rig.leftArm.end)
        var path = Path()
        for r in [7.0, 10.5] { path.addPath(TickPath.arc(hand, r, from: 195, to: 255)) }
        return path
    }

    /// By the tapping foot.
    private var tapLines: Path {
        let foot = look.body(look.rig.rightLeg.end)
        let center = CGPoint(x: foot.x + 2, y: foot.y)
        var path = Path()
        for r in [6.0, 9.0] { path.addPath(TickPath.arc(center, r, from: -70, to: -20)) }
        return path
    }

    private var zees: Path {
        var path = Path()
        for (origin, size) in [(CGPoint(x: 70, y: look.centerY - 40), 6.0), (CGPoint(x: 80, y: look.centerY - 50), 4.5)] {
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + size, y: origin.y))
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + size))
            path.addLine(to: CGPoint(x: origin.x + size, y: origin.y + size))
        }
        return path
    }

    private var star: some View {
        let center = CGPoint(x: 50 + look.shift, y: look.ringTop - 23)
        let shape = TickPath.star(at: center, points: 5, outer: 5.5, inner: 5.5 * 0.45)
        let twinkle = look.motion.twinkle
        return ZStack {
            Ink(shape).fill(look.palette.effects)
            Ink(shape).stroke(look.palette.eyes, lineWidth: 1.2)
        }
        .scaleEffect(1 + 0.25 * twinkle, anchor: UnitPoint(x: center.x / 100, y: center.y / 100))
        .rotationEffect(.degrees(12 * twinkle), anchor: UnitPoint(x: center.x / 100, y: center.y / 100))
    }
}
