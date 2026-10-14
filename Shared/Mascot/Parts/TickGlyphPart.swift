import SwiftUI

/// Under 40 pt, just the head: the ring, the crown and two eyes that still
/// show the mood, and a mouth when there's room. The smallest (16 px) is
/// solid shapes only.
struct TickGlyphPart: View {
    let look: TickLook
    let mouth: Bool

    var body: some View {
        if mouth { head } else { tiny }
    }

    private var head: some View {
        let c = CGPoint(x: 50, y: 58)
        let r = 32.0, rim = 10.0
        let top = c.y - r - rim / 2
        let button = Path(roundedRect: CGRect(x: 35, y: top - 20, width: 30, height: 15), cornerRadius: 6)
        let face = TickPath.circle(c, r)
        let left = min(1, max(0, look.progress))
        return ZStack(alignment: .topLeading) {
            Ink(Path(roundedRect: CGRect(x: 45.5, y: top - 7, width: 9, height: 9), cornerRadius: 1.5)).fill(look.palette.ring)
            Ink(button).fill(look.palette.crown)
            Ink(button).stroke(look.palette.eyes, lineWidth: 3)
            Ink(face).fill(look.palette.face)
            Ink(face).stroke(look.palette.track, lineWidth: rim)
            Ink(face).stroke(look.palette.doneGold, lineWidth: rim).opacity(look.rig.gold)
            Ink(face).stroke(look.palette.ringingRed, lineWidth: rim).opacity(look.rig.alarm)
            Group {
                if left >= 0.999 {
                    Ink(face).stroke(look.palette.ring, lineWidth: rim)
                } else if left > 0.005 {
                    Ink(TickPath.arc(c, r, from: -90, to: -90 + 360 * left))
                        .stroke(look.palette.ring, style: StrokeStyle(lineWidth: rim, lineCap: .round))
                }
            }
            .opacity(look.arcOpacity)
            Ink(TickPath.circle(c, r + rim / 2)).stroke(look.palette.eyes, lineWidth: 2.4)
            TickEyesPart(look: look, center: CGPoint(x: c.x, y: c.y - 6), scale: 1.45)
            TickMouthPart(look: look, center: CGPoint(x: c.x, y: c.y + 10), scale: 1.4)
        }
    }

    /// A terracotta ring, a mustard crown and two dark eyes, filling the square.
    private var tiny: some View {
        let c = CGPoint(x: 50, y: 55)
        var eyes = Path()
        for side in [-1.0, 1.0] { eyes.addPath(TickPath.circle(CGPoint(x: c.x + side * 10, y: c.y - 2), 5.5)) }
        return ZStack(alignment: .topLeading) {
            Ink(Path(CGRect(x: 43, y: c.y - 45, width: 14, height: 7))).fill(look.palette.ring)
            Ink(Path(roundedRect: CGRect(x: 30, y: 4, width: 40, height: 9), cornerRadius: 3)).fill(look.palette.crown)
            Ink(TickPath.circle(c, 40)).fill(look.palette.ring)
            Ink(TickPath.circle(c, 26)).fill(look.palette.face)
            Ink(eyes).fill(look.palette.eyes)
        }
    }
}
