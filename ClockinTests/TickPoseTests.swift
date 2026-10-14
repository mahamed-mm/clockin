import Foundation
import Testing
@testable import Clockin

/// Which Tick shows for each moment.
struct TickPoseTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func session(_ phase: SessionPhase, paused: Bool = false, endsIn: TimeInterval = 600) -> ActiveSession {
        ActiveSession(id: UUID(), name: "Essay", phase: phase, plannedDuration: 1500,
                      focusStartedAt: now.addingTimeInterval(-900),
                      state: paused ? .paused(remaining: 600) : .running(endDate: now.addingTimeInterval(endsIn)))
    }

    func finished(_ outcome: FocusOutcome = .completed, longBreak: Bool = false) -> SessionStage {
        .focusComplete(CompletedFocus(id: UUID(), name: "Essay", startedAt: now.addingTimeInterval(-1500),
                                      completedAt: now, focusSeconds: 1500, isLongBreak: longBreak, outcome: outcome))
    }

    @Test func inTheApp() {
        #expect(TickPose.forStage(.idle, overtime: nil, hour: 14) == .ready)
        #expect(TickPose.forStage(.idle, overtime: nil, hour: 23) == .sleeping)
        #expect(TickPose.forStage(.idle, overtime: nil, hour: 5) == .sleeping)
        #expect(TickPose.forStage(.active(session(.focus)), overtime: nil, hour: 23) == .working)
        #expect(TickPose.forStage(.active(session(.focus, paused: true)), overtime: nil, hour: 14) == .waiting)
        #expect(TickPose.forStage(.active(session(.rest)), overtime: nil, hour: 14) == .onBreak)
        #expect(TickPose.forStage(.active(session(.rest, paused: true)), overtime: nil, hour: 14) == .waiting)
    }

    @Test func afterTheBell() {
        #expect(TickPose.forStage(finished(), overtime: 0, hour: 14) == .done)
        #expect(TickPose.forStage(finished(), overtime: 59, hour: 14) == .done)
        #expect(TickPose.forStage(finished(), overtime: 60, hour: 14) == .working)
        #expect(TickPose.forStage(finished(), overtime: nil, hour: 14) == .done)
        // "Finish now" is done, never a set of four's streak.
        #expect(TickPose.forStage(finished(.endedEarly), overtime: nil, hour: 14) == .done)
        #expect(TickPose.forStage(finished(.endedEarly, longBreak: true), overtime: nil, hour: 14) == .done)
        #expect(TickPose.forStage(finished(longBreak: true), overtime: 0, hour: 14) == .streak)
    }

    @Test func onTheLockScreenAndWidget() {
        #expect(TickPose.forLive(phase: .focus, paused: false, done: false) == .working)
        #expect(TickPose.forLive(phase: .focus, paused: true, done: false) == .waiting)
        #expect(TickPose.forLive(phase: .rest, paused: false, done: false) == .onBreak)
        #expect(TickPose.forLive(phase: .focus, paused: false, done: true) == .done)
        #expect(TickPose.forLive(phase: .rest, paused: false, done: true) == .ready)
        #expect(TickPose.forWidget(nil, at: now, hour: 14) == .ready)
        #expect(TickPose.forWidget(session(.focus, endsIn: -1), at: now, hour: 14) == .done)
        #expect(TickPose.forWidget(session(.rest), at: now, hour: 14) == .onBreak)
    }

    @Test func detailFollowsSize() {
        if case .handmade = TickDetail.fitting(points: 180) {} else { Issue.record("180 pt is hand-made") }
        if case .simplified = TickDetail.fitting(points: 60) {} else { Issue.record("60 pt is simplified") }
        if case .glyph(let mouth) = TickDetail.fitting(points: 20) { #expect(mouth) } else { Issue.record("20 pt is a glyph") }
        if case .glyph(let mouth) = TickDetail.fitting(points: 8) { #expect(!mouth) } else { Issue.record("8 pt is a glyph") }
    }

    @Test func historysTickFollowsTheDay() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func session(_ phase: SessionPhase) -> SessionStage {
            .active(ActiveSession(id: UUID(), name: "", phase: phase, plannedDuration: 300, focusStartedAt: start,
                                  state: .running(endDate: start.addingTimeInterval(300))))
        }
        #expect(TickPose.forHistory(session(.focus), fullToday: 2, hour: 14) == .working)
        #expect(TickPose.forHistory(session(.rest), fullToday: 2, hour: 23) == .onBreak)
        // The set of four done: proud, even at night.
        #expect(TickPose.forHistory(.idle, fullToday: 4, hour: 14) == .streak)
        #expect(TickPose.forHistory(.idle, fullToday: 6, hour: 23) == .streak)
        // Night with nothing done: asleep; something done: ready.
        #expect(TickPose.forHistory(.idle, fullToday: 0, hour: 23) == .sleeping)
        #expect(TickPose.forHistory(.idle, fullToday: 1, hour: 23) == .ready)
        #expect(TickPose.forHistory(.idle, fullToday: 0, hour: 9) == .ready)
    }
}
