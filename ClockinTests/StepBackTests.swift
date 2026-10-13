import Foundation
import Testing
@testable import Clockin

/// The running screen fades back round the dial, and only when nothing
/// needs the controls.
struct StepBackTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func session(_ phase: SessionPhase = .focus, endsIn seconds: TimeInterval,
                         paused: Bool = false) -> ActiveSession {
        ActiveSession(id: UUID(), name: "Essay", phase: phase, plannedDuration: 1_500, focusStartedAt: now,
                      state: paused ? .paused(remaining: seconds) : .running(endDate: now.addingTimeInterval(seconds)))
    }

    @Test func aRunningFocusStepsBackUntilPlusFiveCanAppear() throws {
        let window = try #require(StepBack.window(for: session(endsIn: 1_500), lastTouch: now, assistive: false))
        #expect(window.start == now.addingTimeInterval(8))
        #expect(window.end == now.addingTimeInterval(1_200))
    }

    @Test func aBreakStepsBackUntilItEnds() throws {
        let window = try #require(StepBack.window(for: session(.rest, endsIn: 300), lastTouch: now, assistive: false))
        #expect(window.end == now.addingTimeInterval(300))
    }

    @Test func itStaysPutWhenTheControlsAreWanted() {
        // Nothing running, paused, or with VoiceOver or Switch Control.
        #expect(StepBack.window(for: nil, lastTouch: now, assistive: false) == nil)
        #expect(StepBack.window(for: session(endsIn: 900, paused: true), lastTouch: now, assistive: false) == nil)
        #expect(StepBack.window(for: session(endsIn: 1_500), lastTouch: now, assistive: true) == nil)
        // In the last five minutes "+5 min" may show, so the controls stay.
        #expect(StepBack.window(for: session(endsIn: 290), lastTouch: now, assistive: false) == nil)
        #expect(StepBack.window(for: session(endsIn: 305), lastTouch: now, assistive: false) == nil)
    }

    @Test func pausedMetaSaysWhen() {
        let pausedAt = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 36))!
        #expect(Copy.pausedMeta(at: pausedAt, remaining: 754) == "Paused at \(TimeFormat.time(pausedAt))")
        #expect(Copy.pausedMeta(at: nil, remaining: 754) == "Paused · 12:34 left")
    }
}
