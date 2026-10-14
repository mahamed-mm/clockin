import Foundation
import Testing
@testable import Clockin

/// Tick's moves: each starts and ends on the stance, stays inside its
/// square (clear of the dial's knob and the screen edge), and lands its hits.
struct WorkoutMoveTests {
    /// The stance each move is drawn from: worn-out moves from hands on knees.
    static func params(for move: WorkoutMove) -> WorkoutParams {
        WorkoutSamples.params(left: [.wipe, .weakJab].contains(move) ? 30 : 900)
    }

    /// A point given relative to the body, where it's drawn: squashed and
    /// leaned about the pivot, `follow` of the way for the legs.
    static func placed(_ point: CGPoint, in rig: TickRig, follow: Double = 1) -> CGPoint {
        let sx = 1 + (rig.scaleX - 1) * follow, sy = 1 + (rig.scaleY - 1) * follow
        let x = point.x * sx, y = (rig.centerY + point.y - rig.pivotY) * sy
        let a = rig.lean * follow * .pi / 180
        return CGPoint(x: 50 + x * cos(a) - y * sin(a), y: rig.pivotY + x * sin(a) + y * cos(a))
    }

    @Test(arguments: WorkoutMove.allCases)
    func startsAndEndsOnTheStance(_ move: WorkoutMove) {
        #expect(move.pose(at: 0) == .rest)
        #expect(move.pose(at: move.duration) == .rest)
        // Just before the end it's all but home: no jump back to the stance.
        let last = move.pose(at: move.duration - 0.001)
        #expect(hypot(last.lead.x, last.lead.y) < 0.5 && hypot(last.rear.x, last.rear.y) < 0.5)
        #expect(hypot(last.kick.x, last.kick.y) < 0.5 && abs(last.lean) < 0.5 && abs(last.lift) < 0.5)
        #expect(move.duration > 0.3 && move.duration < 2.5)
    }

    @Test(arguments: WorkoutMove.allCases)
    func staysInsideTheEnvelope(_ move: WorkoutMove) {
        // Every glove, foot and impact line, in Tick units: x 4–100, y 2–100.
        let glove = 3.6 * 2.1 * 1.2
        let params = Self.params(for: move)
        for step in 0...Int(move.duration * 60) {
            let frame = WorkoutFrame(params: params, move: move, at: Double(step) / 60)
            let rig = frame.rig
            for (hand, scale) in [(rig.leftArm.end, rig.leftGloveScale), (rig.rightArm.end, rig.rightGloveScale)] {
                let p = Self.placed(hand, in: rig), r = glove * scale
                #expect(p.x - r >= 4 && p.x + r <= 100 && p.y - r >= 2, "\(move) at \(step): glove \(p)")
            }
            let foot = Self.placed(rig.rightLeg.end, in: rig, follow: rig.legFollow)
            #expect(foot.x + 5 <= 100 && foot.y <= 100, "\(move) at \(step): foot \(foot)")
            if frame.motion.impact > 0 {
                // The lines fan out up to 15 units from the hit, at least 0.7 rad off straight out.
                let hit = Self.placed(frame.motion.impactAt, in: rig)
                let away = atan2(frame.motion.impactAt.y, frame.motion.impactAt.x)
                for a in [away - 0.7, away + 0.7, away - 1.3, away + 1.3] {
                    let tip = CGPoint(x: hit.x + 15 * cos(a), y: hit.y + 15 * sin(a))
                    #expect(tip.x <= 101 && tip.x >= 4 && tip.y >= 2, "\(move) at \(step): lines \(tip)")
                }
            }
        }
    }

    @Test(arguments: WorkoutMove.allCases)
    func hitsLandAtFullReach(_ move: WorkoutMove) {
        for hit in move.hits {
            #expect(move.impact(at: hit.at)?.amount == 1)
            #expect(move.impact(at: hit.at + 0.2) == nil || move.hits.count > 1)
            // The glove or foot is out as it lands, not on its way back in.
            let pose = move.pose(at: hit.at)
            let out = switch hit.limb {
            case .lead: hypot(pose.lead.x, pose.lead.y)
            case .rear: hypot(pose.rear.x, pose.rear.y)
            case .leadFoot: hypot(pose.kick.x, pose.kick.y)
            }
            #expect(out > 6, "\(move) lands at \(hit.at) with only \(out)")
        }
    }

    @Test func punchesAndKicksLandHits() {
        let striking: [WorkoutMove] = [.jab, .cross, .hook, .uppercut, .frontKick, .sideKick, .lightJab, .weakJab, .flurry]
        for move in WorkoutMove.allCases {
            #expect(move.hits.isEmpty != striking.contains(move), "\(move)")
        }
        #expect(WorkoutMove.flurry.hits.count == 6)
        #expect(WorkoutMove.duck.impact(at: 0.2) == nil)
    }

    @Test func aTiredPunchReachesLess() {
        let full = WorkoutMove.jab.pose(at: 0.12)
        let tired = full.reaching(0.6)
        #expect(abs(tired.lead.x - full.lead.x * 0.6) < 1e-9)
        #expect(tired.lean == full.lean)
    }

    @Test func anArmStraightensAsItReaches() {
        let arm = TickRig.Limb(root: CGPoint(x: 28, y: 5), bend: CGPoint(x: 41, y: 17), end: CGPoint(x: 25, y: 5))
        let out = TickRig.reaching(arm, by: CGPoint(x: 20, y: 0))
        #expect(out.end == CGPoint(x: 45, y: 5))
        // The elbow is pulled toward the line from shoulder to glove.
        #expect(abs(out.bend.y - 5) < abs(arm.bend.y - 5))
        #expect(TickRig.reaching(arm, by: .zero) == arm)
    }

    @Test func aHitSqueezesTheEyes() {
        let params = WorkoutSamples.params(left: 900)
        let landing = WorkoutFrame(params: params, move: .jab, at: 0.12)
        #expect(landing.face.eyes == .squeezed)
        #expect(landing.motion.impact == 1)
        #expect(landing.rig.scaleX > TickRig(workout: params).scaleX)
        #expect(WorkoutFrame(params: params, move: .jab, at: 0.5).face.eyes != .squeezed)
    }
}
