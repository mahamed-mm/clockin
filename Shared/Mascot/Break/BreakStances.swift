import Foundation

/// Tick's stances for a break spent other than resting: up off the ground,
/// the mug put away, the gloves and headphones off.
extension TickRig {
    /// Breathing: standing tall and still, arms loose at its sides.
    static var breathing: TickRig {
        var rig = TickRig(.ready)
        let l = leftShoulder, r = rightShoulder
        rig.centerY = 51
        rig.lean = 0
        rig.leftArm = Limb(root: l, bend: CGPoint(x: -37, y: 17), end: CGPoint(x: -28, y: 30))
        rig.rightArm = Limb(root: r, bend: CGPoint(x: 37, y: 17), end: CGPoint(x: 28, y: 30))
        rig.leftLeg = .straight(CGPoint(x: -7, y: hipY), CGPoint(x: -9, y: 40))
        rig.rightLeg = .straight(CGPoint(x: 7, y: hipY), CGPoint(x: 9, y: 40))
        return rig
    }
}

extension TickFace {
    /// Breathing: eyes closed, a small easy smile.
    static var breathing: TickFace {
        TickFace(eyes: .closed, brows: .none, mouth: .content, browHandAngle: 80, browHand: 1)
    }
}
