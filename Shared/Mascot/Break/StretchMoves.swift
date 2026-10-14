import SwiftUI

/// One moment of a stretch, as offsets from the standing stance: where each
/// hand goes, how the body leans, rises and lengthens, the shoulders, and
/// where Tick looks. All zero is the stance, which every stretch starts
/// and ends on.
struct StretchPose: Animatable, Equatable, Sendable {
    /// The left and right hands, in Tick units from where the stance holds them.
    var left = CGPoint.zero
    var right = CGPoint.zero
    /// Extra lean, degrees, about the feet.
    var lean = 0.0
    /// The body raised (negative) or dropped, in Tick units; the feet stay put.
    var lift = 0.0
    /// 0...1 of standing taller and narrower, reaching.
    var stretch = 0.0
    /// 0...1 of the shoulders up round the ears.
    var shrug = 0.0
    /// The eyes and mouth turned to one side, in Tick units (right is positive).
    var gaze = 0.0
    /// 0...1 of the eyes closing.
    var eyesShut = 0.0
    /// 0...1 of a yawn.
    var yawn = 0.0
    /// 0...1 of the hands circling at the wrists, round where they are.
    var circle = 0.0

    static let rest = StretchPose()

    var animatableData: RigVector {
        get { RigVector([left.x, left.y, right.x, right.y, lean, lift, stretch, shrug, gaze, eyesShut, yawn, circle]) }
        set {
            let v = newValue.values
            guard v.count == 12 else { return }
            left = CGPoint(x: v[0], y: v[1]); right = CGPoint(x: v[2], y: v[3])
            lean = v[4]; lift = v[5]; stretch = v[6]; shrug = v[7]; gaze = v[8]; eyesShut = v[9]; yawn = v[10]
            circle = v[11]
        }
    }
}

/// The stretches Tick leads on a break. Each is a slow keyframed run of
/// `StretchPose`, a little over 20 seconds with holds, sampled at any time
/// (so a break opened mid-stretch lands on the right moment), starting and
/// ending on the stance. Gloves off, mug away.
enum StretchMove: String, CaseIterable, Sendable {
    /// The whole of Tick tilting slowly side to side, eyes half closed.
    case neckRoll
    /// Shoulders up round the ears, held, and dropped, three times.
    case shoulderShrug
    /// Both hands up overhead, reaching tall, twice.
    case reachUp
    /// One arm over the top, leaning away, then the other.
    case sideStretch
    /// Hands up in front, circling at the wrists.
    case wristCircles
    /// A hand shading the eyes, looking far off, then the eyes resting shut.
    case eyeRest
    /// After a break: a quick reach up and a yawn, then ready.
    case backToWork

    /// A break's routine, in the order Tick does them.
    static let routine: [StretchMove] = [.neckRoll, .shoulderShrug, .reachUp, .sideStretch, .wristCircles, .eyeRest]

    var duration: TimeInterval { Self.timelines[self]!.duration }

    /// The pose `t` seconds in; the stance before and after.
    func pose(at t: TimeInterval) -> StretchPose {
        let timeline = Self.timelines[self]!
        guard t > 0, t < timeline.duration else { return .rest }
        var pose = timeline.value(time: t)
        if pose.circle > 0 {
            // Small circles at each wrist, the hands going opposite ways round.
            let angle = 2 * .pi * t / Self.circleTime
            let r = 3.5 * pose.circle
            pose.left.x += r * cos(angle)
            pose.left.y += r * sin(angle)
            pose.right.x -= r * cos(angle)
            pose.right.y += r * sin(angle)
        }
        return pose
    }

    /// Seconds per wrist circle.
    static let circleTime = 1.4

    /// Held for Reduce Motion and Low Power Mode: the stretch at its fullest.
    var stillPose: StretchPose {
        switch self {
        case .neckRoll: StretchPose(lean: -9, gaze: -2.5, eyesShut: 0.6)
        case .shoulderShrug: StretchPose(shrug: 1)
        case .reachUp, .backToWork: StretchPose(left: Self.overheadLeft, right: Self.overheadRight, lift: -2, stretch: 1)
        case .sideStretch: StretchPose(right: Self.overTheTop, lean: -12, gaze: -2)
        case .wristCircles: StretchPose(left: Self.inFrontLeft, right: Self.inFrontRight)
        case .eyeRest: StretchPose(right: Self.visor, gaze: 4)
        }
    }

    // Where the hands go, from where the stance holds them (±28, 30 from the body's centre).
    private static let overheadLeft = CGPoint(x: 18, y: -66)
    private static let overheadRight = CGPoint(x: -18, y: -66)
    private static let overTheTop = CGPoint(x: -30, y: -62)
    private static let overTheTopLeft = CGPoint(x: 30, y: -62)
    private static let inFrontLeft = CGPoint(x: 15, y: -12)
    private static let inFrontRight = CGPoint(x: -15, y: -12)
    /// The right hand flat over the brow, shading the eyes.
    private static let visor = CGPoint(x: -12, y: -46)

    // MARK: Keyframes

    /// Made once: building a timeline is the costly part, sampling it is cheap.
    nonisolated(unsafe) private static let timelines: [StretchMove: KeyframeTimeline<StretchPose>] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.makeTimeline()) })

    private func makeTimeline() -> KeyframeTimeline<StretchPose> {
        switch self {
        case .neckRoll:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.lean) {
                    LinearKeyframe(0, duration: 1)
                    CubicKeyframe(-9, duration: 3)
                    LinearKeyframe(-9, duration: 1.5)
                    CubicKeyframe(9, duration: 5)
                    LinearKeyframe(9, duration: 1.5)
                    CubicKeyframe(-9, duration: 5)
                    LinearKeyframe(-9, duration: 1.5)
                    CubicKeyframe(0, duration: 3)
                    LinearKeyframe(0, duration: 1.5)
                }
                KeyframeTrack(\.gaze) {
                    LinearKeyframe(0, duration: 1)
                    CubicKeyframe(-2.5, duration: 3)
                    LinearKeyframe(-2.5, duration: 1.5)
                    CubicKeyframe(2.5, duration: 5)
                    LinearKeyframe(2.5, duration: 1.5)
                    CubicKeyframe(-2.5, duration: 5)
                    LinearKeyframe(-2.5, duration: 1.5)
                    CubicKeyframe(0, duration: 3)
                    LinearKeyframe(0, duration: 1.5)
                }
                KeyframeTrack(\.eyesShut) {
                    LinearKeyframe(0, duration: 1)
                    CubicKeyframe(0.6, duration: 1.5)
                    LinearKeyframe(0.6, duration: 18)
                    CubicKeyframe(0, duration: 1.5)
                    LinearKeyframe(0, duration: 1.5)
                }
            }
        case .shoulderShrug:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.shrug) {
                    LinearKeyframe(0, duration: 1.5)
                    // Three times: up, hold, drop, rest.
                    CubicKeyframe(1, duration: 1.3)
                    LinearKeyframe(1, duration: 1.7)
                    CubicKeyframe(0, duration: 0.9)
                    LinearKeyframe(0, duration: 1.6)
                    CubicKeyframe(1, duration: 1.3)
                    LinearKeyframe(1, duration: 1.7)
                    CubicKeyframe(0, duration: 0.9)
                    LinearKeyframe(0, duration: 1.6)
                    CubicKeyframe(1, duration: 1.3)
                    LinearKeyframe(1, duration: 1.7)
                    CubicKeyframe(0, duration: 0.9)
                    LinearKeyframe(0, duration: 4)
                }
                // Eyes squeezed shut while the shoulders are up.
                KeyframeTrack(\.eyesShut) {
                    LinearKeyframe(0, duration: 2.8)
                    CubicKeyframe(1, duration: 0.4)
                    LinearKeyframe(1, duration: 1.3)
                    CubicKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 3.4)
                    CubicKeyframe(1, duration: 0.4)
                    LinearKeyframe(1, duration: 1.3)
                    CubicKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 3.4)
                    CubicKeyframe(1, duration: 0.4)
                    LinearKeyframe(1, duration: 1.3)
                    CubicKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 4.5)
                }
            }
        case .reachUp:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.left) {
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.overheadLeft, duration: 2.5)
                    LinearKeyframe(Self.overheadLeft, duration: 4)
                    CubicKeyframe(.zero, duration: 2.5)
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.overheadLeft, duration: 2.5)
                    LinearKeyframe(Self.overheadLeft, duration: 4)
                    CubicKeyframe(.zero, duration: 2.5)
                    LinearKeyframe(.zero, duration: 2)
                }
                KeyframeTrack(\.right) {
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.overheadRight, duration: 2.5)
                    LinearKeyframe(Self.overheadRight, duration: 4)
                    CubicKeyframe(.zero, duration: 2.5)
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.overheadRight, duration: 2.5)
                    LinearKeyframe(Self.overheadRight, duration: 4)
                    CubicKeyframe(.zero, duration: 2.5)
                    LinearKeyframe(.zero, duration: 2)
                }
                KeyframeTrack(\.stretch) {
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(1, duration: 2.5)
                    LinearKeyframe(1, duration: 4)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(1, duration: 2.5)
                    LinearKeyframe(1, duration: 4)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 2)
                }
                KeyframeTrack(\.lift) {
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(-2, duration: 2.5)
                    LinearKeyframe(-2, duration: 4)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(-2, duration: 2.5)
                    LinearKeyframe(-2, duration: 4)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 2)
                }
                KeyframeTrack(\.eyesShut) {
                    LinearKeyframe(0, duration: 4)
                    CubicKeyframe(1, duration: 0.5)
                    LinearKeyframe(1, duration: 3)
                    CubicKeyframe(0, duration: 0.5)
                    LinearKeyframe(0, duration: 6.5)
                    CubicKeyframe(1, duration: 0.5)
                    LinearKeyframe(1, duration: 3)
                    CubicKeyframe(0, duration: 0.5)
                    LinearKeyframe(0, duration: 4)
                }
            }
        case .sideStretch:
            KeyframeTimeline(initialValue: .rest) {
                // The right arm over, leaning left; then the left arm over, leaning right.
                KeyframeTrack(\.right) {
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.overTheTop, duration: 2.5)
                    LinearKeyframe(Self.overTheTop, duration: 4.5)
                    CubicKeyframe(.zero, duration: 2.5)
                    LinearKeyframe(.zero, duration: 13)
                }
                KeyframeTrack(\.left) {
                    LinearKeyframe(.zero, duration: 12.5)
                    CubicKeyframe(Self.overTheTopLeft, duration: 2.5)
                    LinearKeyframe(Self.overTheTopLeft, duration: 4.5)
                    CubicKeyframe(.zero, duration: 2.5)
                    LinearKeyframe(.zero, duration: 2)
                }
                KeyframeTrack(\.lean) {
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(-12, duration: 2.5)
                    LinearKeyframe(-12, duration: 4.5)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(10, duration: 2.5)
                    LinearKeyframe(10, duration: 4.5)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 2)
                }
                KeyframeTrack(\.gaze) {
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(-2, duration: 2.5)
                    LinearKeyframe(-2, duration: 4.5)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(2, duration: 2.5)
                    LinearKeyframe(2, duration: 4.5)
                    CubicKeyframe(0, duration: 2.5)
                    LinearKeyframe(0, duration: 2)
                }
            }
        case .wristCircles:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.left) {
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.inFrontLeft, duration: 2)
                    LinearKeyframe(Self.inFrontLeft, duration: 15)
                    CubicKeyframe(.zero, duration: 2)
                    LinearKeyframe(.zero, duration: 1.5)
                }
                KeyframeTrack(\.right) {
                    LinearKeyframe(.zero, duration: 1.5)
                    CubicKeyframe(Self.inFrontRight, duration: 2)
                    LinearKeyframe(Self.inFrontRight, duration: 15)
                    CubicKeyframe(.zero, duration: 2)
                    LinearKeyframe(.zero, duration: 1.5)
                }
                KeyframeTrack(\.circle) {
                    LinearKeyframe(0, duration: 3.5)
                    CubicKeyframe(1, duration: 1)
                    LinearKeyframe(1, duration: 13)
                    CubicKeyframe(0, duration: 1)
                    LinearKeyframe(0, duration: 3.5)
                }
            }
        case .eyeRest:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.right) {
                    LinearKeyframe(.zero, duration: 1)
                    CubicKeyframe(Self.visor, duration: 1.5)
                    LinearKeyframe(Self.visor, duration: 9.5)
                    CubicKeyframe(.zero, duration: 1.5)
                    LinearKeyframe(.zero, duration: 6.5)
                }
                KeyframeTrack(\.gaze) {
                    LinearKeyframe(0, duration: 1.5)
                    CubicKeyframe(4, duration: 1)
                    LinearKeyframe(4, duration: 9)
                    CubicKeyframe(0, duration: 1.5)
                    LinearKeyframe(0, duration: 7)
                }
                KeyframeTrack(\.eyesShut) {
                    LinearKeyframe(0, duration: 13.5)
                    CubicKeyframe(1, duration: 0.8)
                    LinearKeyframe(1, duration: 4)
                    CubicKeyframe(0, duration: 0.7)
                    LinearKeyframe(0, duration: 1)
                }
            }
        case .backToWork:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.left) {
                    CubicKeyframe(Self.overheadLeft, duration: 0.7)
                    LinearKeyframe(Self.overheadLeft, duration: 0.8)
                    CubicKeyframe(.zero, duration: 0.9)
                }
                KeyframeTrack(\.right) {
                    CubicKeyframe(Self.overheadRight, duration: 0.7)
                    LinearKeyframe(Self.overheadRight, duration: 0.8)
                    CubicKeyframe(.zero, duration: 0.9)
                }
                KeyframeTrack(\.stretch) {
                    CubicKeyframe(1, duration: 0.7)
                    LinearKeyframe(1, duration: 0.8)
                    CubicKeyframe(0, duration: 0.9)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-2, duration: 0.7)
                    LinearKeyframe(-2, duration: 0.8)
                    CubicKeyframe(0, duration: 0.9)
                }
                KeyframeTrack(\.eyesShut) {
                    CubicKeyframe(1, duration: 0.5)
                    LinearKeyframe(1, duration: 1.1)
                    CubicKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 0.4)
                }
                KeyframeTrack(\.yawn) {
                    CubicKeyframe(1, duration: 0.5)
                    LinearKeyframe(1, duration: 1.1)
                    CubicKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 0.4)
                }
            }
        }
    }
}

extension TickRig {
    /// The stance with a stretch's moment on top: hands moved (each arm
    /// straightening as it reaches), shoulders up, the body leaned, lifted
    /// and lengthened, the feet kept on the ground.
    func applying(_ pose: StretchPose) -> TickRig {
        var rig = self
        // Shrugging lifts the shoulders and the hands with them, elbows out a little.
        let up = CGPoint(x: 0, y: -10 * pose.shrug)
        for (keyPath, side) in [(\TickRig.leftArm, -1.0), (\TickRig.rightArm, 1.0)] {
            rig[keyPath: keyPath].root.y -= 6 * pose.shrug
            rig[keyPath: keyPath].bend.y -= 8 * pose.shrug
            rig[keyPath: keyPath].bend.x += side * 4 * pose.shrug
        }
        rig.leftArm = Self.raising(Self.reaching(rig.leftArm, by: CGPoint(x: pose.left.x + up.x, y: pose.left.y + up.y)),
                                   side: -1)
        rig.rightArm = Self.raising(Self.reaching(rig.rightArm, by: CGPoint(x: pose.right.x + up.x, y: pose.right.y + up.y)),
                                    side: 1)
        rig.lean += pose.lean
        // Shoulders up, the neck sinks in a little.
        rig.scaleX *= (1 - 0.03 * pose.stretch) * (1 + 0.03 * pose.shrug)
        rig.scaleY *= (1 + 0.06 * pose.stretch) * (1 - 0.04 * pose.shrug)
        rig.centerY += pose.lift
        let planted = legFollow * pose.lift
        rig.leftLeg.end.y -= planted
        rig.leftLeg.bend.y -= planted / 2
        rig.rightLeg.end.y -= planted
        rig.rightLeg.bend.y -= planted / 2
        return rig
    }

    /// An arm whose hand goes up high: the elbow swings out round the
    /// outside of the ring, so the arm reaches up past the face, not across it.
    static func raising(_ arm: Limb, side: Double) -> Limb {
        let high = min(1, max(0, (arm.root.y - arm.end.y) / 36))
        guard high > 0 else { return arm }
        var arm = arm
        let outside = CGPoint(x: side * 46, y: (arm.root.y + arm.end.y) / 2 - 6)
        arm.bend.x += (outside.x - arm.bend.x) * high
        arm.bend.y += (outside.y - arm.bend.y) * high
        return arm
    }

    /// Standing for a break spent stretching or breathing: tall and still,
    /// arms loose at its sides, the mug, gloves and headphones put away.
    static var standing: TickRig { .breathing }
}

extension TickFace {
    /// Stretching: easy, sleepy-eyed, content.
    static var stretching: TickFace { TickFace(.onBreak) }

    /// The face with a stretch's moment on it: turned, eyes closing, yawning.
    func applying(_ pose: StretchPose) -> TickFace {
        var face = self
        face.gazeX += pose.gaze
        face.blink = max(face.blink, pose.eyesShut)
        if pose.yawn > 0.5 { face.mouth = .oh }
        return face
    }
}
