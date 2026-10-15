import Foundation

/// What Tick is watching on the Focus screen while it waits: the knob being
/// dragged, or the name being typed. Only while ready and idle; the face
/// springs to it and back, so frames are drawn only as it moves.
enum TickAttention: Equatable, Sendable {
    case none
    /// The knob, dragged to `minutes` (5...60), `angle` degrees clockwise from 12.
    case knob(minutes: Int, angle: Double)
    /// The name field, below the dial.
    case nameField

    /// How far the eyes reach, in Tick units.
    static let reachX = 3.5
    static let reachY = 2.5

    /// Where Tick sits on the dial, as a fraction of its side (the Focus screen's layout).
    static let tickOnDial = CGPoint(x: 0.9, y: 0.88)
    /// The knob's track, as a fraction of the dial's side from its centre.
    static let knobRadius = 0.36

    /// The face, turned to look: eyes toward the knob or the field, and a
    /// raised brow when the knob reaches either end of the dial.
    func applied(to face: TickFace) -> TickFace {
        var face = face
        switch self {
        case .none:
            break
        case .knob(let minutes, let angle):
            let gaze = Self.gaze(towardKnobAt: angle)
            face.gazeX = gaze.x
            face.gazeY = gaze.y
            if minutes <= SessionLength.minuteRange.lowerBound || minutes >= SessionLength.minuteRange.upperBound {
                face.brows = .singleRaised
            }
        case .nameField:
            // Down and to the left, where the field is.
            face.gazeX = -Self.reachX * 0.8
            face.gazeY = Self.reachY
        }
        return face
    }

    /// Eyes toward the knob at `angle`, from where Tick leans on the dial.
    static func gaze(towardKnobAt angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        let knob = CGPoint(x: 0.5 + knobRadius * sin(radians), y: 0.5 - knobRadius * cos(radians))
        let dx = knob.x - tickOnDial.x, dy = knob.y - tickOnDial.y
        let length = max(0.001, (dx * dx + dy * dy).squareRoot())
        return CGPoint(x: reachX * dx / length, y: reachY * dy / length)
    }
}
