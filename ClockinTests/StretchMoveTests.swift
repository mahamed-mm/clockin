import Foundation
import Testing
@testable import Clockin

/// Tick's stretches: each starts and ends on the stance, moves smoothly,
/// stays inside its square (clear of the dial's knob and the screen edge),
/// and lasts long enough to do along with it.
struct StretchMoveTests {
    /// Every hand on the stance with the stretch's moment on top, where it's drawn.
    static func hands(_ move: StretchMove, at t: TimeInterval) -> [CGPoint] {
        let rig = TickRig.standing.applying(move.pose(at: t))
        return [rig.leftArm.end, rig.rightArm.end].map { WorkoutMoveTests.placed($0, in: rig) }
    }

    @Test(arguments: StretchMove.allCases)
    func startsAndEndsOnTheStance(_ move: StretchMove) {
        #expect(move.pose(at: 0) == .rest)
        #expect(move.pose(at: move.duration) == .rest)
        let last = move.pose(at: move.duration - 0.001)
        #expect(hypot(last.left.x, last.left.y) < 0.5 && hypot(last.right.x, last.right.y) < 0.5)
        #expect(abs(last.lean) < 0.5 && abs(last.lift) < 0.5 && last.shrug < 0.05 && last.eyesShut < 0.05)
    }

    @Test(arguments: StretchMove.allCases)
    func lastsLongEnoughToDoAlong(_ move: StretchMove) {
        if move == .backToWork {
            #expect(abs(move.duration - 2.4) < 0.01)
        } else {
            #expect(move.duration >= 20 && move.duration <= 30, "\(move): \(move.duration) s")
        }
    }

    @Test(arguments: StretchMove.allCases)
    func movesWithoutJumps(_ move: StretchMove) {
        var previous = Self.hands(move, at: 0)
        var lean = 0.0
        // Slow stretches move under 2 units a frame; the quick reach after a break, under 4.
        let most = move == .backToWork ? 4.0 : 2.0
        for step in 1...Int(move.duration * 60) {
            let t = Double(step) / 60
            let hands = Self.hands(move, at: t)
            for (a, b) in zip(previous, hands) {
                #expect(hypot(a.x - b.x, a.y - b.y) < most, "\(move) at \(t)")
            }
            let pose = move.pose(at: t)
            #expect(abs(pose.lean - lean) < 1, "\(move) leans too fast at \(t)")
            previous = hands
            lean = pose.lean
        }
    }

    @Test(arguments: StretchMove.allCases)
    func staysInsideTheEnvelope(_ move: StretchMove) {
        // Bare hands, in Tick units: x 4–100, y 2–100.
        let hand = 3.6
        for step in 0...Int(move.duration * 30) {
            for p in Self.hands(move, at: Double(step) / 30) {
                #expect(p.x - hand >= 4 && p.x + hand <= 100 && p.y - hand >= 2 && p.y + hand <= 100,
                        "\(move) at \(Double(step) / 30): hand \(p)")
            }
        }
        let still = TickRig.standing.applying(move.stillPose)
        for p in [still.leftArm.end, still.rightArm.end].map({ WorkoutMoveTests.placed($0, in: still) }) {
            #expect(p.x - hand >= 4 && p.x + hand <= 100 && p.y - hand >= 2, "\(move) still: \(p)")
        }
    }

    @Test func stillPosesShowTheStretch() {
        for move in StretchMove.allCases {
            #expect(move.stillPose != .rest, "\(move)")
        }
    }

    @Test func theStanceHasNothingInItsHands() {
        let rig = TickRig.standing
        #expect(rig.mug == 0 && rig.gloves == 0 && rig.headphones == 0 && rig.lean == 0)
    }

    @Test func theFaceFollowsTheStretch() {
        let face = TickFace.stretching.applying(StretchMove.backToWork.pose(at: 1))
        #expect(face.mouth == .oh)
        #expect(face.blink > 0.9)
        let looking = TickFace.stretching.applying(StretchMove.eyeRest.pose(at: 6))
        #expect(looking.gazeX > 3)
    }

    @Test func wristsCircle() {
        let move = StretchMove.wristCircles
        let a = move.pose(at: 10), b = move.pose(at: 10 + StretchMove.circleTime / 2)
        #expect(hypot(a.left.x - b.left.x, a.left.y - b.left.y) > 5)
        // A full circle later the hands are back.
        let c = move.pose(at: 10 + StretchMove.circleTime)
        #expect(hypot(a.left.x - c.left.x, a.left.y - c.left.y) < 0.01)
    }
}
