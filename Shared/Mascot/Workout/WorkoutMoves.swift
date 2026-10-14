import SwiftUI

/// One moment of a move, as offsets from the stance: where each glove and
/// the lead foot go, how the body leans, turns, squashes and dips. All
/// zero is the stance itself, which every move starts and ends on.
struct WorkoutPose: Animatable, Equatable, Sendable {
    /// The lead (right) glove, in Tick units from where the stance holds it.
    var lead = CGPoint.zero
    /// The rear (left) glove.
    var rear = CGPoint.zero
    /// Added to each glove's size: punching toward you makes it bigger.
    var leadScale = 0.0
    var rearScale = 0.0
    /// The lead foot, from where it stands.
    var kick = CGPoint.zero
    /// Extra lean, degrees (clockwise is into the punch).
    var lean = 0.0
    /// Turning into a punch, -1...1: the body narrows and the face turns.
    var twist = 0.0
    /// Squashed wider and lower (positive) or stretched taller (negative).
    var squash = 0.0
    /// The body dropped (positive) or raised, in Tick units; the feet stay put.
    var lift = 0.0

    static let rest = WorkoutPose()

    var animatableData: RigVector {
        get { RigVector([lead.x, lead.y, rear.x, rear.y, leadScale, rearScale, kick.x, kick.y, lean, twist, squash, lift]) }
        set {
            let v = newValue.values
            guard v.count == 12 else { return }
            lead = CGPoint(x: v[0], y: v[1]); rear = CGPoint(x: v[2], y: v[3])
            leadScale = v[4]; rearScale = v[5]; kick = CGPoint(x: v[6], y: v[7])
            lean = v[8]; twist = v[9]; squash = v[10]; lift = v[11]
        }
    }

    /// Gloves and foot reaching only `reach` of the way (a tired punch).
    func reaching(_ reach: Double) -> WorkoutPose {
        var pose = self
        pose.lead = CGPoint(x: lead.x * reach, y: lead.y * reach)
        pose.rear = CGPoint(x: rear.x * reach, y: rear.y * reach)
        pose.kick = CGPoint(x: kick.x * reach, y: kick.y * reach)
        pose.leadScale *= reach
        pose.rearScale *= reach
        return pose
    }
}

/// What lands a hit.
enum WorkoutLimb: Sendable { case lead, rear, leadFoot }

/// Tick's moves. Each is a short keyframed run of `WorkoutPose`, sampled
/// at any time (so a session opened mid-move lands on the right frame),
/// that starts and ends on the stance. Times are at full tempo.
enum WorkoutMove: String, CaseIterable, Sendable {
    /// The stance with a small bounce, between punches.
    case guardBounce
    /// The lead glove straight out.
    case jab
    /// The rear glove across, turning into it.
    case cross
    /// The lead glove in a flat curve across the front.
    case hook
    /// Dips, then rises as the lead glove comes up.
    case uppercut
    /// The lead foot up and forward, leaning back.
    case frontKick
    /// The lead foot out to the side, tilting away.
    case sideKick
    /// Dips and sways under a punch.
    case duck
    // Warming up.
    case armCircle
    case stretch
    case lightJab
    // Worn out.
    /// A glove across the forehead.
    case wipe
    /// A slow, short jab from hands on knees.
    case weakJab
    /// Gloves on: tapping them together twice.
    case gloveTap
    /// The final push: six fast punches, lead and rear in turn.
    case flurry

    struct Hit: Equatable, Sendable {
        var at: TimeInterval
        var limb: WorkoutLimb
    }

    /// When each punch or kick lands.
    var hits: [Hit] {
        switch self {
        case .jab, .lightJab: [Hit(at: 0.12, limb: .lead)]
        case .cross: [Hit(at: 0.17, limb: .rear)]
        case .hook: [Hit(at: 0.24, limb: .lead)]
        case .uppercut: [Hit(at: 0.3, limb: .lead)]
        case .frontKick: [Hit(at: 0.28, limb: .leadFoot)]
        case .sideKick: [Hit(at: 0.3, limb: .leadFoot)]
        case .weakJab: [Hit(at: 0.4, limb: .lead)]
        case .flurry: (0..<6).map { Hit(at: 0.1 + 0.28 * Double($0), limb: $0.isMultiple(of: 2) ? .lead : .rear) }
        case .guardBounce, .duck, .armCircle, .stretch, .wipe, .gloveTap: []
        }
    }

    var duration: TimeInterval { Self.timelines[self]!.duration }

    /// The pose `t` seconds in; the stance before and after.
    func pose(at t: TimeInterval) -> WorkoutPose {
        let timeline = Self.timelines[self]!
        guard t > 0, t < timeline.duration else { return .rest }
        return timeline.value(time: t)
    }

    /// How hard a hit is landing at `t`, 0...1, and with what: it peaks as
    /// the punch lands and fades over a tenth of a second.
    func impact(at t: TimeInterval) -> (amount: Double, limb: WorkoutLimb)? {
        var best: (amount: Double, limb: WorkoutLimb)?
        for hit in hits {
            let d = t - hit.at
            let amount = d < 0 ? max(0, 1 + d / 0.04) : max(0, 1 - d / 0.12)
            if amount > 0, amount > best?.amount ?? 0 { best = (amount, hit.limb) }
        }
        return best
    }

    // MARK: Keyframes

    /// Made once: building a timeline is the costly part, sampling it is cheap.
    nonisolated(unsafe) private static let timelines: [WorkoutMove: KeyframeTimeline<WorkoutPose>] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.makeTimeline()) })

    private func makeTimeline() -> KeyframeTimeline<WorkoutPose> {
        switch self {
        case .guardBounce:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-1.5, duration: 0.2)
                    CubicKeyframe(0.5, duration: 0.2)
                    CubicKeyframe(0, duration: 0.15)
                }
            }
        case .jab: Self.jab(reach: 1, out: 0.12, back: 0.2)
        case .lightJab: Self.jab(reach: 0.55, out: 0.12, back: 0.22)
        case .cross:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.rear) {
                    CubicKeyframe(CGPoint(x: 36, y: -9), duration: 0.17)
                    LinearKeyframe(CGPoint(x: 36, y: -9), duration: 0.05)
                    CubicKeyframe(.zero, duration: 0.22)
                }
                KeyframeTrack(\.rearScale) {
                    CubicKeyframe(0.25, duration: 0.17)
                    LinearKeyframe(0.25, duration: 0.05)
                    CubicKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.twist) {
                    CubicKeyframe(1, duration: 0.17)
                    LinearKeyframe(1, duration: 0.05)
                    CubicKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(6, duration: 0.17)
                    LinearKeyframe(6, duration: 0.05)
                    CubicKeyframe(0, duration: 0.22)
                }
                // The lead glove pulls back to guard the chin.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: -5, y: 5), duration: 0.17)
                    LinearKeyframe(CGPoint(x: -5, y: 5), duration: 0.05)
                    CubicKeyframe(.zero, duration: 0.22)
                }
            }
        case .hook:
            KeyframeTimeline(initialValue: .rest) {
                // Out and up a little, then a flat swing across the front.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: 8, y: -6), duration: 0.1)
                    CubicKeyframe(CGPoint(x: -4, y: -9), duration: 0.08)
                    CubicKeyframe(CGPoint(x: -20, y: -4), duration: 0.06)
                    LinearKeyframe(CGPoint(x: -20, y: -4), duration: 0.04)
                    CubicKeyframe(.zero, duration: 0.24)
                }
                KeyframeTrack(\.twist) {
                    CubicKeyframe(0.4, duration: 0.1)
                    CubicKeyframe(-0.8, duration: 0.14)
                    LinearKeyframe(-0.8, duration: 0.04)
                    CubicKeyframe(0, duration: 0.24)
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(3, duration: 0.1)
                    CubicKeyframe(-4, duration: 0.14)
                    LinearKeyframe(-4, duration: 0.04)
                    CubicKeyframe(0, duration: 0.24)
                }
            }
        case .uppercut:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.lift) {
                    CubicKeyframe(4, duration: 0.18)
                    CubicKeyframe(-3, duration: 0.12)
                    LinearKeyframe(-3, duration: 0.05)
                    CubicKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.squash) {
                    CubicKeyframe(0.5, duration: 0.18)
                    CubicKeyframe(-0.4, duration: 0.12)
                    LinearKeyframe(-0.4, duration: 0.05)
                    CubicKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: -4, y: 10), duration: 0.18)
                    CubicKeyframe(CGPoint(x: -7, y: -26), duration: 0.12)
                    LinearKeyframe(CGPoint(x: -7, y: -26), duration: 0.05)
                    CubicKeyframe(.zero, duration: 0.2)
                }
            }
        case .frontKick:
            KeyframeTimeline(initialValue: .rest) {
                // Knee up, foot out toward you and up, leaning back.
                KeyframeTrack(\.kick) {
                    CubicKeyframe(CGPoint(x: 6, y: -12), duration: 0.16)
                    CubicKeyframe(CGPoint(x: 13, y: -20), duration: 0.12)
                    LinearKeyframe(CGPoint(x: 13, y: -20), duration: 0.06)
                    CubicKeyframe(CGPoint(x: 5, y: -8), duration: 0.12)
                    CubicKeyframe(.zero, duration: 0.14)
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(-7, duration: 0.28)
                    LinearKeyframe(-7, duration: 0.06)
                    CubicKeyframe(0, duration: 0.26)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-1.5, duration: 0.28)
                    LinearKeyframe(-1.5, duration: 0.06)
                    CubicKeyframe(0, duration: 0.26)
                }
            }
        case .sideKick:
            KeyframeTimeline(initialValue: .rest) {
                // Chamber, then straight out to the right, tilting away.
                KeyframeTrack(\.kick) {
                    CubicKeyframe(CGPoint(x: 4, y: -14), duration: 0.16)
                    CubicKeyframe(CGPoint(x: 22, y: -13), duration: 0.14)
                    LinearKeyframe(CGPoint(x: 22, y: -13), duration: 0.08)
                    CubicKeyframe(CGPoint(x: 4, y: -10), duration: 0.12)
                    CubicKeyframe(.zero, duration: 0.12)
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(-12, duration: 0.3)
                    LinearKeyframe(-12, duration: 0.08)
                    CubicKeyframe(0, duration: 0.24)
                }
            }
        case .duck:
            KeyframeTimeline(initialValue: .rest) {
                KeyframeTrack(\.lift) {
                    CubicKeyframe(6, duration: 0.18)
                    CubicKeyframe(6, duration: 0.16)
                    CubicKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(-7, duration: 0.18)
                    CubicKeyframe(6, duration: 0.16)
                    CubicKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.squash) {
                    CubicKeyframe(0.35, duration: 0.18)
                    CubicKeyframe(0.35, duration: 0.16)
                    CubicKeyframe(0, duration: 0.2)
                }
            }
        case .armCircle:
            KeyframeTimeline(initialValue: .rest) {
                // Both gloves round a small circle, opposite ways.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: 6, y: -7), duration: 0.3)
                    CubicKeyframe(CGPoint(x: 0, y: -14), duration: 0.3)
                    CubicKeyframe(CGPoint(x: -6, y: -7), duration: 0.3)
                    CubicKeyframe(.zero, duration: 0.3)
                }
                KeyframeTrack(\.rear) {
                    CubicKeyframe(CGPoint(x: -6, y: -7), duration: 0.3)
                    CubicKeyframe(CGPoint(x: 0, y: -14), duration: 0.3)
                    CubicKeyframe(CGPoint(x: 6, y: -7), duration: 0.3)
                    CubicKeyframe(.zero, duration: 0.3)
                }
            }
        case .stretch:
            KeyframeTimeline(initialValue: .rest) {
                // Both gloves overhead, standing tall, held, then back.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: -11, y: -36), duration: 0.45)
                    LinearKeyframe(CGPoint(x: -11, y: -36), duration: 0.6)
                    CubicKeyframe(.zero, duration: 0.45)
                }
                KeyframeTrack(\.rear) {
                    CubicKeyframe(CGPoint(x: -1, y: -45), duration: 0.45)
                    LinearKeyframe(CGPoint(x: -1, y: -45), duration: 0.6)
                    CubicKeyframe(.zero, duration: 0.45)
                }
                KeyframeTrack(\.squash) {
                    CubicKeyframe(-0.4, duration: 0.45)
                    LinearKeyframe(-0.4, duration: 0.6)
                    CubicKeyframe(0, duration: 0.45)
                }
            }
        case .wipe:
            KeyframeTimeline(initialValue: .rest) {
                // Up to the forehead, a swipe across, back down to the knee.
                KeyframeTrack(\.rear) {
                    CubicKeyframe(CGPoint(x: 18, y: -38), duration: 0.35)
                    CubicKeyframe(CGPoint(x: 36, y: -40), duration: 0.3)
                    CubicKeyframe(.zero, duration: 0.4)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-2, duration: 0.35)
                    LinearKeyframe(-2, duration: 0.3)
                    CubicKeyframe(0, duration: 0.4)
                }
            }
        case .weakJab:
            KeyframeTimeline(initialValue: .rest) {
                // Half up off the knee, a slow short jab, back down.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: 4, y: -16), duration: 0.25)
                    CubicKeyframe(CGPoint(x: 13, y: -19), duration: 0.15)
                    LinearKeyframe(CGPoint(x: 13, y: -19), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.4)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-3, duration: 0.4)
                    LinearKeyframe(-3, duration: 0.1)
                    CubicKeyframe(0, duration: 0.4)
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(-4, duration: 0.4)
                    LinearKeyframe(-4, duration: 0.1)
                    CubicKeyframe(0, duration: 0.4)
                }
            }
        case .gloveTap:
            KeyframeTimeline(initialValue: .rest) {
                // The gloves meet in front, twice.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: -16, y: 7), duration: 0.25)
                    CubicKeyframe(CGPoint(x: -12, y: 6), duration: 0.12)
                    CubicKeyframe(CGPoint(x: -16, y: 7), duration: 0.12)
                    CubicKeyframe(CGPoint(x: -12, y: 6), duration: 0.12)
                    CubicKeyframe(.zero, duration: 0.3)
                }
                KeyframeTrack(\.rear) {
                    CubicKeyframe(CGPoint(x: 14, y: -3), duration: 0.25)
                    CubicKeyframe(CGPoint(x: 10, y: -2), duration: 0.12)
                    CubicKeyframe(CGPoint(x: 14, y: -3), duration: 0.12)
                    CubicKeyframe(CGPoint(x: 10, y: -2), duration: 0.12)
                    CubicKeyframe(.zero, duration: 0.3)
                }
            }
        case .flurry:
            KeyframeTimeline(initialValue: .rest) {
                // Lead, rear, lead...: each out in 0.1 s, back by the next.
                KeyframeTrack(\.lead) {
                    CubicKeyframe(CGPoint(x: 11, y: -4), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.14)
                    LinearKeyframe(.zero, duration: 0.32)
                    CubicKeyframe(CGPoint(x: 11, y: -4), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.14)
                    LinearKeyframe(.zero, duration: 0.32)
                    CubicKeyframe(CGPoint(x: 11, y: -4), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.14)
                    LinearKeyframe(.zero, duration: 0.32)
                }
                KeyframeTrack(\.rear) {
                    LinearKeyframe(.zero, duration: 0.28)
                    CubicKeyframe(CGPoint(x: 32, y: -8), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.14)
                    LinearKeyframe(.zero, duration: 0.32)
                    CubicKeyframe(CGPoint(x: 32, y: -8), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.14)
                    LinearKeyframe(.zero, duration: 0.32)
                    CubicKeyframe(CGPoint(x: 32, y: -8), duration: 0.1)
                    CubicKeyframe(.zero, duration: 0.14)
                    LinearKeyframe(.zero, duration: 0.32)
                }
                KeyframeTrack(\.twist) {
                    CubicKeyframe(-0.3, duration: 0.1)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(0.8, duration: 0.1)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(-0.3, duration: 0.1)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(0.8, duration: 0.1)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(-0.3, duration: 0.1)
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(0.8, duration: 0.1)
                    CubicKeyframe(0, duration: 0.18)
                }
            }
        }
    }

    private static func jab(reach: Double, out: TimeInterval, back: TimeInterval) -> KeyframeTimeline<WorkoutPose> {
        let fist = CGPoint(x: 11 * reach, y: -4 * reach)
        return KeyframeTimeline(initialValue: .rest) {
            KeyframeTrack(\.lead) {
                CubicKeyframe(fist, duration: out)
                LinearKeyframe(fist, duration: 0.04)
                CubicKeyframe(.zero, duration: back)
            }
            KeyframeTrack(\.leadScale) {
                CubicKeyframe(0.15 * reach, duration: out)
                LinearKeyframe(0.15 * reach, duration: 0.04)
                CubicKeyframe(0, duration: back)
            }
            KeyframeTrack(\.lean) {
                CubicKeyframe(2 * reach, duration: out)
                LinearKeyframe(2 * reach, duration: 0.04)
                CubicKeyframe(0, duration: back)
            }
        }
    }
}

extension TickRig {
    /// The stance with a move's moment on top: gloves and foot moved (each
    /// arm straightening as it reaches), the body leaned, turned, squashed
    /// and dipped, the feet kept on the ground.
    func applying(_ pose: WorkoutPose) -> TickRig {
        var rig = self
        rig.rightArm = Self.reaching(rightArm, by: pose.lead)
        rig.leftArm = Self.reaching(leftArm, by: pose.rear)
        rig.rightGloveScale += pose.leadScale
        rig.leftGloveScale += pose.rearScale
        rig.lean += pose.lean
        rig.scaleX *= 1 + 0.08 * pose.squash - 0.06 * abs(pose.twist)
        rig.scaleY *= 1 - 0.08 * pose.squash
        rig.centerY += pose.lift
        // The feet stay where they stand as the body dips or rises.
        let planted = legFollow * pose.lift
        rig.leftLeg.end.y -= planted
        rig.leftLeg.bend.y -= planted / 2
        rig.rightLeg.end.y -= planted
        rig.rightLeg.bend.y -= planted / 2
        // A kick: the foot out, the knee bent up on the way.
        rig.rightLeg.end.x += pose.kick.x
        rig.rightLeg.end.y += pose.kick.y
        rig.rightLeg.bend.x += pose.kick.x * 0.6
        rig.rightLeg.bend.y += pose.kick.y * 0.8
        return rig
    }

    /// An arm with its hand moved by `offset`: the elbow goes along, and
    /// straightens the further the hand reaches.
    static func reaching(_ arm: Limb, by offset: CGPoint) -> Limb {
        guard offset != .zero else { return arm }
        let end = CGPoint(x: arm.end.x + offset.x, y: arm.end.y + offset.y)
        let carried = CGPoint(x: arm.bend.x + offset.x / 2, y: arm.bend.y + offset.y / 2)
        let middle = CGPoint(x: (arm.root.x + end.x) / 2, y: (arm.root.y + end.y) / 2)
        let straight = 0.8 * min(1, hypot(offset.x, offset.y) / 18)
        let bend = CGPoint(x: carried.x + (middle.x - carried.x) * straight,
                           y: carried.y + (middle.y - carried.y) * straight)
        return Limb(root: arm.root, bend: bend, end: end)
    }
}
