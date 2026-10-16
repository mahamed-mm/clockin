import SwiftUI

/// A thought ticked off: a pen line drawn through the text, line by line,
/// left to right, as `progress` goes from 0 to 1. Drawn by the text itself,
/// so wrapped thoughts get one stroke per line and nothing is laid out again.
struct PenStroke: TextRenderer, Animatable {
    var progress: Double
    var color: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout { context.draw(line) }
        let rects = layout.map { $0.typographicBounds.rect }
        for (from, to) in Self.strokes(lines: rects, progress: progress) {
            var path = Path()
            path.move(to: from)
            // A slight lift in the middle, like a hand.
            let middle = CGPoint(x: (from.x + to.x) / 2, y: from.y - 1.2)
            path.addQuadCurve(to: to, control: middle)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    /// Where the stroke runs on each line at `progress`: through the middle
    /// of the letters, the lines filled one after another by their width.
    static func strokes(lines: [CGRect], progress: Double) -> [(CGPoint, CGPoint)] {
        let total = lines.reduce(0) { $0 + $1.width }
        var left = min(1, max(0, progress)) * total
        var strokes: [(CGPoint, CGPoint)] = []
        for line in lines where left > 0 {
            let length = min(line.width, left)
            left -= length
            let y = line.minY + line.height * 0.55
            strokes.append((CGPoint(x: line.minX, y: y), CGPoint(x: line.minX + length, y: y)))
        }
        return strokes
    }
}
