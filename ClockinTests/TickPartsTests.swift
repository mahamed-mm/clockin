import SwiftUI
import Testing
@testable import Clockin

/// Tick drawn from its parts: every state, at every detail.
@MainActor
struct TickPartsTests {
    @Test(arguments: TickPose.allCases)
    func everyStateDrawsAtEveryDetail(_ pose: TickPose) {
        for size in [180.0, 60, 20, 8] {
            let renderer = ImageRenderer(content: TickFigure(pose: pose, palette: .standard).frame(width: size, height: size))
            renderer.scale = 2
            #expect(renderer.uiImage != nil, "\(pose) at \(size) pt")
        }
    }

    @Test func detailFollowsSize() {
        #expect(TickDetail.fitting(points: 180) == .handmade)
        #expect(TickDetail.fitting(points: 60) == .simplified)
        #expect(TickDetail.fitting(points: 20) == .glyph(mouth: true))
        #expect(TickDetail.fitting(points: 8) == .glyph(mouth: false))
    }

    @Test func arcsAreSampledFromStartToEnd() {
        let arc = TickPath.arc(CGPoint(x: 50, y: 50), 10, from: -90, to: 0)
        let box = arc.boundingRect
        // A quarter from twelve to three o'clock.
        #expect(abs(box.minX - 50) < 0.01 && abs(box.maxX - 60) < 0.01)
        #expect(abs(box.minY - 40) < 0.01 && abs(box.maxY - 50) < 0.01)
    }
}
