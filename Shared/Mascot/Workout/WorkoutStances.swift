import Foundation

/// Tick's stances for a workout: gloves on, headphones on, turned a little
/// to the right, away from the dial, so every punch and kick goes that way.
extension TickRig {
    /// Between moves, for how tired Tick is: guard, gloves by the face (and
    /// lower as it tires), leaning in; or, worn out, hands on knees.
    init(workout params: WorkoutParams) {
        self.init(.working)
        gloves = 1
        headphones = 1
        let l = Self.leftShoulder, r = Self.rightShoulder
        switch params.stance {
        case .guardUp:
            let drop = params.guardDrop
            centerY = 53 + 0.25 * params.hunch
            lean = 4 + params.hunch
            // The rear glove guards the chin; the lead glove is out front, to the right.
            leftArm = Limb(root: l, bend: CGPoint(x: -38, y: 20 + 0.5 * drop), end: CGPoint(x: -11, y: 16 + drop))
            rightArm = Limb(root: r, bend: CGPoint(x: 40, y: 18 + 0.5 * drop), end: CGPoint(x: 21, y: 6 + drop))
            // A boxer's stance: feet apart, the lead foot forward.
            leftLeg = .straight(CGPoint(x: -7, y: Self.hipY), CGPoint(x: -13, y: 38 - 0.25 * params.hunch))
            rightLeg = .straight(CGPoint(x: 7, y: Self.hipY), CGPoint(x: 13, y: 38 - 0.25 * params.hunch))
            rightFoot = -8
        case .handsOnKnees:
            // Bent over, knees bent out past the body, gloves resting on them.
            centerY = 56; lean = 8; pivotY = 88; legFollow = 0
            leftLeg = Limb(root: CGPoint(x: -8, y: 20), bend: CGPoint(x: -26, y: 26), end: CGPoint(x: -17, y: 35))
            rightLeg = Limb(root: CGPoint(x: 8, y: 20), bend: CGPoint(x: 26, y: 26), end: CGPoint(x: 17, y: 35))
            leftArm = Limb(root: l, bend: CGPoint(x: -36, y: 14), end: CGPoint(x: -25, y: 23))
            rightArm = Limb(root: r, bend: CGPoint(x: 34, y: 12), end: CGPoint(x: 22, y: 22))
        }
    }

    /// Paused mid-workout: arms crossed, gloves still on, foot tapping.
    static var glovedWaiting: TickRig {
        var rig = TickRig(.waiting)
        rig.gloves = 1
        rig.headphones = 1
        return rig
    }

    /// Done after a workout: the champion, gloves raised overhead.
    static var champion: TickRig {
        var rig = TickRig(.done)
        rig.gloves = 1
        let l = Self.leftShoulder, r = Self.rightShoulder
        rig.leftArm = Limb(root: l, bend: CGPoint(x: -36, y: -10), end: CGPoint(x: -30, y: -30))
        rig.rightArm = Limb(root: r, bend: CGPoint(x: 36, y: -10), end: CGPoint(x: 30, y: -30))
        return rig
    }
}

/// Named workout stances, for the gallery and the render script.
enum WorkoutSamples {
    /// Tick at a moment of a 25-minute session, by time left.
    static func params(left: TimeInterval, planned: TimeInterval = 1500) -> WorkoutParams {
        WorkoutParams(.at(planned: planned, remaining: left))
    }

    /// A stance with the face that goes with it.
    static func sample(left: TimeInterval) -> (rig: TickRig, face: TickFace) {
        let params = params(left: left)
        return (TickRig(workout: params), TickFace(workout: params.face, flush: params.flush))
    }

    static let stances: [(name: String, rig: TickRig, face: TickFace)] = [
        ("warm-up", sample(left: 1490).rig, sample(left: 1490).face),
        ("strong", sample(left: 900).rig, sample(left: 900).face),
        ("tired", sample(left: 240).rig, sample(left: 240).face),
        ("tired, late", sample(left: 70).rig, sample(left: 70).face),
        ("exhausted", sample(left: 30).rig, sample(left: 30).face),
        ("paused", .glovedWaiting, TickFace(.waiting)),
        ("champion", .champion, TickFace(.done)),
    ]

    /// The four faces, on the strong stance.
    static let faces: [(name: String, rig: TickRig, face: TickFace)] = [
        ("determined", sample(left: 900).rig, TickFace(workout: .determined)),
        ("effort", sample(left: 900).rig, TickFace(workout: .determined, hit: true)),
        ("strained", sample(left: 70).rig, TickFace(workout: .strained, flush: 0.8)),
        ("panting", sample(left: 30).rig, TickFace(workout: .panting, flush: 1)),
    ]
}
