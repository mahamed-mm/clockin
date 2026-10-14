import Foundation
import Testing
@testable import Clockin

/// What a touch on Tick does.
struct TickTouchTests {
    @Test func theCrownWorksTheTimer() {
        #expect(TickTouch.action(for: .crown, pose: .ready, crownWorks: true) == .crown)
        #expect(TickTouch.action(for: .crown, pose: .working, crownWorks: true) == .crown)
        #expect(TickTouch.action(for: .crown, pose: .waiting, crownWorks: true) == .crown)
        // Where the crown does nothing (History), it's just more of Tick to poke.
        #expect(TickTouch.action(for: .crown, pose: .hello, crownWorks: false) == .poke)
    }

    @Test func theBodyGiggles() {
        for pose in TickPose.allCases where pose != .ringing {
            #expect(TickTouch.action(for: .body, pose: pose, crownWorks: true) == .poke)
        }
    }

    @Test func anyTouchStopsTheAlarm() {
        #expect(TickTouch.action(for: .body, pose: .ringing, crownWorks: true) == .dismissAlarm)
        #expect(TickTouch.action(for: .crown, pose: .ringing, crownWorks: true) == .dismissAlarm)
        #expect(TickTouch.action(for: .crown, pose: .ringing, crownWorks: false) == .dismissAlarm)
    }

    @Test func theCrownIsAboveTheBody() {
        for pose in TickPose.allCases {
            let rig = TickRig(pose)
            let crown = TickTouch.crownCenter(rig), body = TickTouch.bodyCenter(rig)
            #expect(crown.y < body.y - 25, "\(pose)")
            #expect((0...100).contains(crown.x) && (0...100).contains(crown.y), "\(pose)")
        }
        // Leaning back on a break tips the crown back with the body.
        #expect(TickTouch.crownCenter(TickRig(.onBreak)).x < 45)
    }

    @Test func everyStateIsSpoken() {
        #expect(Set(TickPose.allCases.map(\.spokenState)).count == TickPose.allCases.count)
    }
}
