import Foundation
import Testing
@testable import Clockin

/// Tick's pose and face numbers: one per state, and they animate.
struct TickRigTests {
    @Test(arguments: TickPose.allCases)
    func everyStateHasAPose(_ pose: TickPose) {
        let rig = TickRig(pose)
        #expect((40...62).contains(rig.centerY))
        #expect((-20...20).contains(rig.lean))
        #expect(rig.scaleX > 0.8 && rig.scaleY > 0.8)
        // Hands and feet stay inside the 100-unit square.
        for limb in [rig.leftArm, rig.rightArm, rig.leftLeg, rig.rightLeg] {
            #expect((0...100).contains(50 + limb.end.x))
            #expect((0...100).contains(rig.centerY + limb.end.y))
        }
        #expect(rig.animatableData.values.count == TickRig(.ready).animatableData.values.count)
    }

    @Test func eachStateBringsItsOwnProps() {
        #expect(TickRig(.working).headphones == 1)
        #expect(TickRig(.onBreak).mug == 1)
        #expect(TickRig(.streak).star == 1)
        #expect(TickRig(.sleeping).zees == 1)
        #expect(TickRig(.done).gold == 1 && TickRig(.done).sparkles == 1)
        #expect(TickRig(.ringing).alarm == 1)
        #expect(TickRig(.ready).headphones == 0 && TickRig(.ready).alarm == 0)
        // Only on a break do the legs stay on the ground as the body leans back.
        #expect(TickPose.allCases.filter { TickRig($0).legFollow == 0 } == [.onBreak])
    }

    @Test(arguments: TickPose.allCases)
    func everyStateHasAFace(_ pose: TickPose) {
        let face = TickFace(pose)
        #expect(face.blink == 0)
        #expect((-180...180).contains(face.browHandAngle))
        // Waiting swaps the clock-hand brow for one plain raised brow.
        #expect((face.browHand == 0) == (pose == .waiting))
    }

    @Test func aPoseSpringsThroughTheInBetween() {
        let ready = TickRig(.ready), working = TickRig(.working)
        var halfway = ready
        var data = ready.animatableData
        data += (working.animatableData - ready.animatableData).scaled(by: 0.5)
        halfway.animatableData = data
        #expect(halfway.lean == (ready.lean + working.lean) / 2)
        #expect(halfway.headphones == 0.5)
        #expect(halfway.rightArm.end.y == (ready.rightArm.end.y + working.rightArm.end.y) / 2)
        // Setting the numbers back gives the same pose.
        var copy = working
        copy.animatableData = working.animatableData
        #expect(copy == working)
    }

    @Test func zeroStandsInForAnyLength() {
        let rig = TickRig(.done).animatableData
        #expect(rig + .zero == rig)
        #expect(rig - rig == .zero)
    }

    @Test func theSheetsRing() {
        #expect(TickPose.ready.sheetProgress == 1)
        #expect(TickPose.done.sheetProgress == 0)
        #expect(TickPose.working.sheetProgress == 0.6)
    }
}
