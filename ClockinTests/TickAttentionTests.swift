import Foundation
import Testing
@testable import Clockin

/// Tick watching the knob and the name field.
struct TickAttentionTests {
    let ready = TickFace(.ready)

    @Test func nothingToWatchLeavesTheFace() {
        #expect(TickAttention.none.applied(to: ready) == ready)
    }

    @Test func eyesFollowTheKnobRoundTheDial() {
        // Tick leans on the dial's lower right: the knob at 12 is up and to the left.
        let top = TickAttention.gaze(towardKnobAt: 0)
        #expect(top.x < 0 && top.y < 0)
        // At 3 o'clock it's above, a little left.
        let right = TickAttention.gaze(towardKnobAt: 90)
        #expect(right.y < 0 && abs(right.x) < abs(right.y))
        // At 9 it's straight across to the left.
        let left = TickAttention.gaze(towardKnobAt: 270)
        #expect(left.x < -3 && abs(left.y) < 1.5)
        for angle in stride(from: 0.0, to: 360, by: 15) {
            let gaze = TickAttention.gaze(towardKnobAt: angle)
            #expect(abs(gaze.x) <= TickAttention.reachX + 0.001 && abs(gaze.y) <= TickAttention.reachY + 0.001)
        }
    }

    @Test func aBrowGoesUpAtEitherEnd() {
        #expect(TickAttention.knob(minutes: 25, angle: 150).applied(to: ready).brows == .none)
        #expect(TickAttention.knob(minutes: 5, angle: 30).applied(to: ready).brows == .singleRaised)
        #expect(TickAttention.knob(minutes: 60, angle: 0).applied(to: ready).brows == .singleRaised)
    }

    @Test func theFieldIsDownAndLeft() {
        let face = TickAttention.nameField.applied(to: ready)
        #expect(face.gazeX < 0 && face.gazeY > 0)
        #expect(face.eyes == ready.eyes && face.mouth == ready.mouth)
    }

    @Test func gazeYSprings() {
        var face = ready
        face.gazeY = 2
        var moved = face
        moved.animatableData = face.animatableData
        #expect(moved.gazeY == 2)
    }
}
