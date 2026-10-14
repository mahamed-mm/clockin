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

    // MARK: Workout

    @Test func workoutStancesWearGloves() {
        for (name, rig, _) in WorkoutSamples.stances {
            #expect(rig.gloves == 1, "\(name)")
            #expect(rig.leftGloveScale == 1 && rig.rightGloveScale == 1, "\(name)")
            // The gloves, about 8 units round, stay in Tick's square, clear of the dial.
            for hand in [rig.leftArm.end, rig.rightArm.end] {
                let point = Self.placed(hand, in: rig)
                #expect((12...92).contains(point.x), "\(name) \(point)")
                #expect((10...92).contains(point.y), "\(name) \(point)")
            }
        }
        #expect(TickPose.allCases.allSatisfy { TickRig($0).gloves == 0 })
    }

    @Test func tiringLowersTheGuard() {
        let fresh = TickRig(workout: WorkoutSamples.params(left: 900))
        let tired = TickRig(workout: WorkoutSamples.params(left: 70))
        #expect(tired.lean > fresh.lean)
        #expect(tired.rightArm.end.y > fresh.rightArm.end.y)
        #expect(WorkoutSamples.params(left: 30).stance == .handsOnKnees)
        #expect(TickRig(workout: WorkoutSamples.params(left: 30)).legFollow == 0)
    }

    @Test func glovesPopOnThroughTheInBetween() {
        let ready = TickRig(.ready), boxing = TickRig(workout: WorkoutSamples.params(left: 900))
        var halfway = ready
        halfway.animatableData = ready.animatableData + (boxing.animatableData - ready.animatableData).scaled(by: 0.5)
        #expect(halfway.gloves == 0.5)
        #expect(halfway.leftGloveScale == 1)
    }

    @Test func workoutFacesTireInStages() {
        let determined = TickFace(workout: .determined)
        let strained = TickFace(workout: .strained, flush: 0.8)
        let panting = TickFace(workout: .panting, flush: 1)
        #expect(determined.mouth == .set && determined.browHandAngle < 0)
        #expect(strained.eyes == .squint && strained.mouth == .gritted)
        #expect(panting.eyes == .tired && panting.mouth == .pant && panting.mouthOpen > 0)
        #expect(panting.flush == 1 && determined.flush == 0)
        // Turned toward the punches, on the right.
        #expect([determined, strained, panting].allSatisfy { $0.gazeX > 0 })
        // A hit screws the eyes shut and puffs the cheeks; panting stays open-mouthed.
        let hit = TickFace(workout: .determined, hit: true)
        #expect(hit.eyes == .squeezed && hit.mouth == .puffed && hit.flush > 0)
        #expect(TickFace(workout: .panting, hit: true).mouth == .pant)
        // The state faces look straight ahead.
        #expect(TickPose.allCases.allSatisfy { TickFace($0).gazeX == 0 && TickFace($0).flush == 0 })
    }

    @Test func faceNumbersAnimate() {
        let calm = TickFace(.working), panting = TickFace(workout: .panting, flush: 1)
        var halfway = calm
        halfway.animatableData = calm.animatableData + (panting.animatableData - calm.animatableData).scaled(by: 0.5)
        #expect(halfway.flush == 0.5 && halfway.gazeX == 1.5 && halfway.mouthOpen == 0.3)
        var copy = panting
        copy.animatableData = panting.animatableData
        #expect(copy == panting)
    }

    /// A point given relative to the body, where it's drawn: leaned about the pivot.
    static func placed(_ point: CGPoint, in rig: TickRig) -> CGPoint {
        let a = rig.lean * .pi / 180
        let x = point.x, y = rig.centerY + point.y - rig.pivotY
        return CGPoint(x: 50 + x * cos(a) - y * sin(a), y: rig.pivotY + x * sin(a) + y * cos(a))
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
