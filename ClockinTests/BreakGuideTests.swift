import Foundation
import Testing
@testable import Clockin

/// The taps that mark a break's steps: each breath turning, each stretch
/// starting and ending, so a step is felt with the eyes shut.
struct BreakGuideTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func guide(_ style: BreakStyle, planned: TimeInterval = 300, from: TimeInterval = 0) -> BreakGuide {
        BreakGuide(activity: TickBreak(planned: planned, endDate: start.addingTimeInterval(planned),
                                       pausedRemaining: nil, style: style, from: from))
    }

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func eachStretchStartingAndEndingIsACue() throws {
        let guide = guide(.stretch)
        let entries = guide.routine.entries
        let first = try #require(entries.first)
        #expect(guide.cue(at: start) == 0)
        #expect(guide.cue(at: at(first.start)) == 1)
        #expect(guide.cue(at: at(first.end - 0.1)) == 1)
        #expect(guide.cue(at: at(first.end)) == 2)
        #expect(guide.cue(at: at(entries[1].start)) == 3)
        // The last stretch ending is the routine done; nothing after it.
        #expect(guide.cue(at: at(guide.routine.end)) == entries.count * 2)
        #expect(guide.cue(at: at(299)) == entries.count * 2)
        let cues = guide.cues(after: start)
        #expect(cues == entries.flatMap { [at($0.start), at($0.end)] })
        // Every change of the dial's words is a cue too.
        #expect(Set(guide.changes(after: start)).isSubset(of: Set(cues)))
    }

    @Test func aStretchStartingTapsFirmerThanOneEnding() {
        let guide = guide(.stretch)
        #expect(guide.strength(ofCue: 1) > guide.strength(ofCue: 2))
        #expect(guide.strength(ofCue: 3) == guide.strength(ofCue: 1))
    }

    @Test func eachBreathTurningIsACue() {
        let guide = guide(.breathe, from: 60)
        #expect(guide.cue(at: at(61)) == 0)
        #expect(guide.cue(at: at(64)) == 1)
        #expect(guide.cue(at: at(70)) == 2)
        #expect(guide.cues(after: at(61)) == guide.changes(after: at(61)))
        // Breathing in taps firmer than breathing out.
        #expect(guide.strength(ofCue: 2) > guide.strength(ofCue: 1))
    }

    @Test func pausedNoCueComes() {
        var activity = TickBreak(planned: 300, endDate: nil, pausedRemaining: 200, style: .stretch)
        var guide = BreakGuide(activity: activity)
        #expect(guide.cues(after: start).isEmpty)
        #expect(guide.cue(at: start) == guide.cue(at: at(500)))
        activity.style = .breathe
        guide = BreakGuide(activity: activity)
        #expect(guide.cues(after: start).isEmpty)
    }

    @Test func aRestHasNoCues() {
        let guide = guide(.rest)
        #expect(guide.cue(at: at(30)) == nil)
        #expect(guide.cues(after: start).isEmpty)
    }
}
