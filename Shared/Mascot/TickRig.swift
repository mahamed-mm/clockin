import SwiftUI

/// Tick's body, as numbers: where the body sits, how it leans and
/// squashes, where each arm and leg goes, and how much of each prop and
/// effect shows. One value per state, and every number animates, so a
/// change of state springs from one pose to the next.
///
/// Positions are in Tick units (the figure is 100 across). Arms and legs
/// are relative to the body's centre, so they travel with it.
struct TickRig: Equatable, Sendable {
    /// The body's centre, down from the top.
    var centerY: Double
    /// Lean in degrees, clockwise, about `pivotY`.
    var lean: Double
    /// Squash and stretch about the pivot.
    var scaleX: Double
    var scaleY: Double
    /// Where the body leans and squashes from: the feet, or the seat.
    var pivotY: Double
    /// 1 when the legs move with the body; 0 when they stay put on the
    /// ground (leaning back on a break).
    var legFollow: Double
    var shadowWidth: Double

    var leftArm: Limb
    var rightArm: Limb
    var leftLeg: Limb
    var rightLeg: Limb
    /// The feet's tilt in degrees, for a tapping toe or feet up.
    var leftFoot: Double
    var rightFoot: Double

    /// Props and effects, 0 hidden to 1 shown.
    var headphones: Double
    var mug: Double
    var star: Double
    var zees: Double
    var sparkles: Double
    /// The alarm: the bright ring, its lines and the vibration.
    var alarm: Double
    /// The all-gold ring of a finished session.
    var gold: Double
    var waveLines: Double
    var tapLines: Double

    /// How far the crown is pressed in, 0 to 1.
    var crownPress: Double = 0

    /// Boxing gloves over the hands, 0 off to 1 on (they pop on and off).
    var gloves: Double = 0
    /// Each glove's size: over 1 when punching toward you.
    var leftGloveScale: Double = 1
    var rightGloveScale: Double = 1

    /// An arm or leg: where it starts on the body, the bend it curves
    /// through, and where it ends, all relative to the body's centre.
    struct Limb: Equatable, Sendable {
        var root: CGPoint
        var bend: CGPoint
        var end: CGPoint

        /// A straight limb, bending at its middle.
        static func straight(_ root: CGPoint, _ end: CGPoint) -> Limb {
            Limb(root: root, bend: CGPoint(x: (root.x + end.x) / 2, y: (root.y + end.y) / 2), end: end)
        }
    }
}

extension TickRig {
    /// Where an arm meets the body.
    static let leftShoulder = CGPoint(x: -28, y: 5)
    static let rightShoulder = CGPoint(x: 28, y: 5)
    /// Where the legs meet the body.
    static let hipY = 22.0

    /// Tick's pose for a state, as drawn on the character sheet.
    init(_ pose: TickPose) {
        func arm(_ shoulder: CGPoint, _ bend: (Double, Double), _ hand: (Double, Double)) -> Limb {
            Limb(root: shoulder, bend: CGPoint(x: bend.0, y: bend.1), end: CGPoint(x: hand.0, y: hand.1))
        }
        func leg(_ hip: Double, _ foot: (Double, Double)) -> Limb {
            .straight(CGPoint(x: hip, y: Self.hipY), CGPoint(x: foot.0, y: foot.1))
        }
        let l = Self.leftShoulder, r = Self.rightShoulder

        self.init(centerY: 52, lean: 0, scaleX: 1, scaleY: 1, pivotY: 92, legFollow: 1, shadowWidth: 40,
                  leftArm: arm(l, (-37, 16), (-20, 28)), rightArm: arm(r, (37, 16), (20, 28)),
                  leftLeg: leg(-7, (-9, 39)), rightLeg: leg(7, (9, 39)), leftFoot: 0, rightFoot: 0,
                  headphones: 0, mug: 0, star: 0, zees: 0, sparkles: 0, alarm: 0, gold: 0, waveLines: 0, tapLines: 0)

        switch pose {
        case .ready:
            lean = 4
            leftArm = arm(l, (-35, 14), (-33, 24))
            rightArm = arm(r, (38, -6), (17, -35))
        case .working:
            centerY = 53; lean = 7
            leftLeg = leg(-7, (-9, 38)); rightLeg = leg(7, (9, 38))
            headphones = 1
        case .waiting:
            centerY = 55; lean = -6
            // Arms crossed over the lower face; one toe up, tapping.
            leftArm = arm(l, (-44, 19), (11, 17))
            rightArm = arm(r, (44, 19), (-11, 19.5))
            leftLeg = leg(-7, (-9, 36)); rightLeg = leg(7, (14, 29))
            rightFoot = -25
            tapLines = 1
        case .done:
            centerY = 46; scaleX = 0.95; scaleY = 1.07; shadowWidth = 28
            leftArm = arm(l, (-35, -6), (-38, -23))
            rightArm = arm(r, (35, -6), (38, -23))
            leftLeg = leg(-6, (-7, 35)); rightLeg = leg(6, (7, 35))
            sparkles = 1; gold = 1
        case .onBreak:
            // Leaning back from the seat, on one hand, the mug in the other;
            // the legs stay stretched out on the ground, crossed at the ankle.
            centerY = 54; lean = -16; pivotY = 76; legFollow = 0; shadowWidth = 56
            leftArm = arm(l, (-35, 18), (-32, 34))
            rightArm = arm(r, (39, 6), (36, -6))
            leftLeg = Limb(root: CGPoint(x: -3, y: 22), bend: CGPoint(x: 12, y: 24), end: CGPoint(x: 26, y: 35))
            rightLeg = Limb(root: CGPoint(x: 3, y: 21), bend: CGPoint(x: 16, y: 21), end: CGPoint(x: 30, y: 32))
            leftFoot = -60; rightFoot = -60
            mug = 1
        case .ringing:
            scaleX = 1.08; scaleY = 0.92
            leftArm = arm(l, (-38, -6), (-14, -34))
            rightArm = arm(r, (38, -6), (14, -34))
            leftLeg = leg(-8, (-12, 39)); rightLeg = leg(8, (12, 39))
            alarm = 1
        case .hello:
            lean = -7
            leftArm = arm(l, (-37, -9), (-40, -31))
            rightArm = arm(r, (35, 14), (33, 24))
            waveLines = 1
        case .interrupted:
            // A kind "oh well" shrug, hands out and open.
            centerY = 55
            leftArm = arm(l, (-34, 16), (-44, 6))
            rightArm = arm(r, (34, 16), (44, 6))
            leftLeg = leg(-5, (-5, 36)); rightLeg = leg(5, (5, 36))
        case .streak:
            // Hands on hips, the star on the crown.
            leftArm = arm(l, (-39, 10), (-26, 18))
            rightArm = arm(r, (39, 10), (26, 18))
            leftLeg = leg(-8, (-14, 39)); rightLeg = leg(8, (14, 39))
            star = 1
        case .sleeping:
            centerY = 60; lean = -10
            leftArm = arm(l, (-32, 14), (-25, 24))
            rightArm = arm(r, (32, 14), (25, 24))
            leftLeg = leg(-7, (-22, 32)); rightLeg = leg(7, (22, 32))
            zees = 1
        }
    }
}

extension TickPose {
    /// The ring on the character sheet: full when ready, draining while
    /// working, empty when the time is up, refilling on a break.
    var sheetProgress: Double {
        switch self {
        case .ready, .hello, .streak, .sleeping: 1
        case .working, .waiting: 0.6
        case .done, .ringing: 0
        case .onBreak: 0.5
        case .interrupted: 0.4
        }
    }
}

// MARK: - Animation

extension TickRig: Animatable {
    var animatableData: RigVector {
        get {
            var values = [centerY, lean, scaleX, scaleY, pivotY, legFollow, shadowWidth, leftFoot, rightFoot,
                          headphones, mug, star, zees, sparkles, alarm, gold, waveLines, tapLines, crownPress,
                          gloves, leftGloveScale, rightGloveScale]
            for limb in [leftArm, rightArm, leftLeg, rightLeg] {
                values += [limb.root.x, limb.root.y, limb.bend.x, limb.bend.y, limb.end.x, limb.end.y]
            }
            return RigVector(values)
        }
        set {
            var values = newValue.values[...]
            guard values.count == Self.numberCount else { return }
            func next() -> Double { values.removeFirst() }
            func nextLimb() -> Limb {
                Limb(root: CGPoint(x: next(), y: next()), bend: CGPoint(x: next(), y: next()), end: CGPoint(x: next(), y: next()))
            }
            centerY = next(); lean = next(); scaleX = next(); scaleY = next(); pivotY = next(); legFollow = next()
            shadowWidth = next(); leftFoot = next(); rightFoot = next()
            headphones = next(); mug = next(); star = next(); zees = next(); sparkles = next(); alarm = next()
            gold = next(); waveLines = next(); tapLines = next(); crownPress = next()
            gloves = next(); leftGloveScale = next(); rightGloveScale = next()
            leftArm = nextLimb(); rightArm = nextLimb(); leftLeg = nextLimb(); rightLeg = nextLimb()
        }
    }

    /// 22 numbers and four limbs of three points.
    private static let numberCount = 22 + 4 * 6
}

/// A list of numbers that SwiftUI can animate: the rig's, and the face's.
struct RigVector: VectorArithmetic, Sendable {
    var values: [Double]

    init(_ values: [Double]) { self.values = values }

    static var zero: RigVector { RigVector([]) }

    // `zero` has no length: it stands for all zeros at whatever length the other side has.
    private static func combine(_ a: RigVector, _ b: RigVector, _ op: (Double, Double) -> Double) -> RigVector {
        let count = max(a.values.count, b.values.count)
        return RigVector((0..<count).map { op(a.values.indices.contains($0) ? a.values[$0] : 0,
                                              b.values.indices.contains($0) ? b.values[$0] : 0) })
    }

    static func + (a: RigVector, b: RigVector) -> RigVector { combine(a, b, +) }
    static func - (a: RigVector, b: RigVector) -> RigVector { combine(a, b, -) }
    static func += (a: inout RigVector, b: RigVector) { a = a + b }
    static func -= (a: inout RigVector, b: RigVector) { a = a - b }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }

    static func == (a: RigVector, b: RigVector) -> Bool {
        combine(a, b, -).values.allSatisfy { $0 == 0 }
    }
}
