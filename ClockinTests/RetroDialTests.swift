import Foundation
import Testing
@testable import Clockin

/// Which of the dial's 60 ticks are lit, which decides when its face is drawn again.
struct RetroDialTests {
    @Test func ticksLightInsideTheArc() {
        #expect(RetroDial.litTicks(value: 0) == 0)
        #expect(RetroDial.litTicks(value: 1) == 60)
        #expect(RetroDial.litTicks(value: 0.5) == 30)
        // The arc has to pass a tick to light it: exactly on the second tick lights only the first.
        #expect(RetroDial.litTicks(value: 1.0 / 60) == 1)
        #expect(RetroDial.litTicks(value: 1.0 / 60 + 0.001) == 2)
        // Out of range clamps, like the arc.
        #expect(RetroDial.litTicks(value: -0.2) == 0)
        #expect(RetroDial.litTicks(value: 1.4) == 60)
    }

    @Test func theFaceStaysPutBetweenTicks() {
        #expect(RetroDial.litTicks(value: 0.402) == RetroDial.litTicks(value: 0.415))
        // A 25-minute session counted down a second at a time lights or
        // clears a tick about once a minute: 26 faces, not 1500.
        let faces = Set((0...1500).map { RetroDial.litTicks(value: DialLength.arcValue(remaining: TimeInterval($0))) })
        #expect(faces.count == 26)
    }
}
