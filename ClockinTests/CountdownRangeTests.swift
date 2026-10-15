import Foundation
import Testing
@testable import Clockin

/// The range live timer text counts down over.
struct CountdownRangeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func runsFromNowToTheEnd() {
        let end = now.addingTimeInterval(750)
        #expect(ClosedRange<Date>.countdown(to: end, from: now) == now...end)
    }

    @Test func anEndAlreadyPastIsEmptyAtNowInsteadOfTrapping() {
        let range = ClosedRange<Date>.countdown(to: now.addingTimeInterval(-30), from: now)
        #expect(range == now...now)
    }

    @Test func anEndRightNowIsEmpty() {
        #expect(ClosedRange<Date>.countdown(to: now, from: now) == now...now)
    }
}
