import SwiftUI

enum FocusLayout {
    /// The dial's side: the height left after everything around it, never
    /// wider than the column and never under `minimum`. When the minimum
    /// doesn't fit, the page scrolls.
    static func dialSide(viewportHeight: CGFloat, chrome: CGFloat, minimum: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(width, max(minimum, viewportHeight - chrome))
    }
}

/// Setting the length by dragging the knob round the dial. The face is a
/// 60-minute kitchen timer: 12 o'clock is 0 and 60, one tick a minute.
enum DialLength {
    /// The angle of a touch from the dial's centre, in radians clockwise
    /// from 12 o'clock (0..<2π).
    static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        let angle = atan2(Double(point.x - center.x), Double(center.y - point.y))
        return angle < 0 ? angle + 2 * .pi : angle
    }

    /// The angle the knob sits at for `minutes`.
    static func angle(forMinutes minutes: Int) -> Double {
        Double(minutes) / 60 * 2 * .pi
    }

    /// Whole minutes on the dial for a touch at `angle`, snapped to five.
    /// While dragging (`previous` set), crossing 12 o'clock holds at the end
    /// the finger came from, so 60 never jumps to 5 or back.
    static func minutes(atAngle angle: Double, previous: Int?) -> Int {
        let range = SessionLength.minuteRange
        let raw = angle / (2 * .pi) * 60
        let step = Double(SessionLength.minuteStep)
        let snapped = Int((raw / step).rounded() * step)
        let minutes = min(max(snapped, range.lowerBound), range.upperBound)
        if let previous, abs(minutes - previous) > 30 {
            return previous > 30 ? range.upperBound : range.lowerBound
        }
        return minutes
    }

    /// Where the knob sits on a dial of `side` points, set to `minutes`.
    static func knobPoint(minutes: Int, side: CGFloat) -> CGPoint {
        let radius = side / 2 * RetroDial.arcRadiusRatio(showsTicks: true)
        let angle = angle(forMinutes: minutes)
        return CGPoint(x: side / 2 + radius * sin(angle), y: side / 2 - radius * cos(angle))
    }

    /// How big the knob's touch target is: the drawn knob, never under 44 points.
    static func grabSize(side: CGFloat) -> CGFloat {
        max(44, side * 0.16)
    }
}

extension View {
    /// Keeps `height` up to date with this view's laid-out height.
    func measuredHeight(_ height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.wrappedValue = $0 }
    }
}
