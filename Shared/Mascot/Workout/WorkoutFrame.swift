import Foundation

/// One drawn moment of the workout: the rig, face and motion for a move
/// `t` seconds in, on the stance for how tired Tick is.
struct WorkoutFrame: Equatable {
    var rig: TickRig
    var face: TickFace
    var motion = TickMotion()

    init(params: WorkoutParams, move: WorkoutMove? = nil, at t: TimeInterval = 0) {
        let pose = move.map { $0.pose(at: t).reaching(params.reach) } ?? .rest
        rig = TickRig(workout: params).applying(pose)
        let hit = move?.impact(at: t)
        let amount = hit?.amount ?? 0
        face = TickFace(workout: params.face, hit: amount > 0.3, flush: params.flush)
        // The face turns with the body.
        face.gazeX += 2 * pose.twist
        if let hit {
            motion.impact = amount
            motion.impactAt = switch hit.limb {
            case .lead: rig.rightArm.end
            case .rear: rig.leftArm.end
            case .leadFoot: rig.rightLeg.end
            }
            // A 6% squash as it lands.
            rig.scaleX *= 1 + 0.06 * amount
            rig.scaleY *= 1 - 0.06 * amount
        }
    }
}
