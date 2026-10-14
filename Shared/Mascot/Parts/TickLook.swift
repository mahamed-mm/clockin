import SwiftUI

/// Everything a part of Tick needs to draw itself: the pose, the face, the
/// time left, the colours and the detail, plus the measurements every part
/// shares. All in Tick units: the parts stack in a 100-unit square that
/// the figure scales to size.
struct TickLook {
    var rig: TickRig
    var face: TickFace
    /// The ring's time left, 0...1.
    var progress: Double
    var palette: TickPalette
    var motion: TickMotion
    var detail: TickDetail

    static let radius = 27.0
    static let rimWidth = 7.0
    static let ground = 92.0

    var radius: Double { Self.radius }
    var rimWidth: Double { Self.rimWidth }

    /// The body's centre, lifted by a hop.
    var centerY: Double { rig.centerY - 6 * motion.hop }
    var center: CGPoint { CGPoint(x: 50, y: centerY) }
    /// The top of the ring, where the crown's stem goes in.
    var ringTop: Double { centerY - radius - rimWidth / 2 }

    var handmade: Bool { if case .handmade = detail { true } else { false } }
    var limbWidth: Double { handmade ? 3.8 : 5 }
    var legWidth: Double { handmade ? 4.8 : 6 }
    var handRadius: Double { handmade ? 3 : 3.6 }
    /// The crown and eyebrow sit a touch off centre when hand-made.
    var shift: Double { handmade ? 1.2 : 0 }

    /// The time left, unless the whole ring is gold or ringing.
    var arcOpacity: Double { 1 - max(rig.gold, rig.alarm) }

    /// A point given relative to the body's centre.
    func body(_ point: CGPoint) -> CGPoint { CGPoint(x: 50 + point.x, y: centerY + point.y) }
}

/// A path already in Tick units, drawn as is.
struct Ink: Shape {
    var path: Path
    init(_ path: Path) { self.path = path }
    func path(in rect: CGRect) -> Path { path }
}

// MARK: - Path helpers

enum TickPath {
    static func circle(_ center: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    static func arc(_ center: CGPoint, _ r: Double, from: Double, to: Double) -> Path {
        // Clockwise on screen from `from` to `to` degrees (0 is three
        // o'clock), as a fine polyline: arcs added to one path stay apart,
        // and a round cap always sits on both ends.
        let steps = max(8, Int(abs(to - from).rounded(.up)))
        var path = Path()
        path.addLines((0...steps).map { step in
            let angle = (from + (to - from) * Double(step) / Double(steps)) * .pi / 180
            return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        })
        return path
    }

    /// An arm or leg: from its root, curving through its bend, to its end.
    static func limb(_ limb: TickRig.Limb, from look: TickLook) -> Path {
        var path = Path()
        path.move(to: look.body(limb.root))
        path.addQuadCurve(to: look.body(limb.end), control: look.body(limb.bend))
        return path
    }

    static func sparkle(at c: CGPoint, radius r: Double) -> Path {
        star(at: c, points: 4, outer: r, inner: r * 0.32)
    }

    static func star(at c: CGPoint, points: Int, outer: Double, inner: Double) -> Path {
        var path = Path()
        for i in 0..<(points * 2) {
            let angle = Double(i) * .pi / Double(points)
            let length = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: c.x + length * sin(angle), y: c.y - length * cos(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
