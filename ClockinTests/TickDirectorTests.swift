import Foundation
import Testing
@testable import Clockin

/// The rules for which Tick shows, and when it changes on its own.
struct TickDirectorTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func session(_ phase: SessionPhase, paused: Bool = false) -> ActiveSession {
        ActiveSession(id: UUID(), name: "Essay", phase: phase, plannedDuration: 1500,
                      focusStartedAt: now.addingTimeInterval(-900),
                      state: paused ? .paused(remaining: 600) : .running(endDate: now.addingTimeInterval(600)))
    }

    func finished(_ outcome: FocusOutcome = .completed, longBreak: Bool = false, planned: TimeInterval? = 1500,
                  focused: TimeInterval = 1500) -> SessionStage {
        .focusComplete(CompletedFocus(id: UUID(), name: "Essay", startedAt: now.addingTimeInterval(-focused),
                                      completedAt: now, focusSeconds: focused, isLongBreak: longBreak,
                                      plannedSeconds: planned, outcome: outcome))
    }

    func director(_ stage: SessionStage, ringing: Bool = false, hour: Int = 14, since: TimeInterval = 0,
                  hello: Date? = nil) -> TickDirector {
        TickDirector(stage: stage, alarmRinging: ringing, hour: hour, stageSince: now.addingTimeInterval(-since),
                     helloUntil: hello)
    }

    @Test func ringingBeatsEverything() {
        for stage in [SessionStage.idle, .active(session(.focus)), finished(), finished(longBreak: true)] {
            #expect(director(stage, ringing: true, hour: 23, hello: now.addingTimeInterval(5)).pose(at: now) == .ringing)
        }
        #expect(director(.idle, ringing: true).nextChange(after: now) == nil)
    }

    @Test func afterFocusItRingsThenIsDone() {
        #expect(director(finished(), ringing: true).pose(at: now) == .ringing)
        #expect(director(finished(), ringing: false).pose(at: now) == .done)
    }

    @Test func afterABreakItRingsThenIsReady() {
        // A finished break leaves the engine idle.
        #expect(director(.idle, ringing: true).pose(at: now) == .ringing)
        #expect(director(.idle, ringing: false).pose(at: now) == .ready)
    }

    @Test func theStreakWaitsForDone() {
        let set = finished(longBreak: true)
        #expect(director(set, since: 0).pose(at: now) == .done)
        #expect(director(set, since: 2.9).pose(at: now) == .done)
        #expect(director(set, since: 3).pose(at: now) == .streak)
        #expect(director(set, since: 0).nextChange(after: now) == now.addingTimeInterval(3))
        // Not for an ordinary session, nor one finished early.
        #expect(director(finished(), since: 10).pose(at: now) == .done)
        #expect(director(finished(.endedEarly, longBreak: true), since: 10).pose(at: now) == .interrupted)
        #expect(director(finished(.endedEarly, longBreak: true)).nextChange(after: now) == nil)
    }

    @Test func theStreakIsDroppedWhenTheStageMovesOn() {
        // Started the break before the streak showed: Tick's on a break.
        #expect(director(.active(session(.rest)), since: 1).pose(at: now) == .onBreak)
    }

    @Test func helloOnceThenReady() {
        let hello = now.addingTimeInterval(TickDirector.helloLength)
        #expect(director(.idle, hello: hello).pose(at: now) == .hello)
        #expect(director(.idle, hello: hello).nextChange(after: now) == hello)
        #expect(director(.idle, hello: hello).pose(at: hello) == .ready)
        // Hello is only for an idle Tick.
        #expect(director(.active(session(.focus)), hello: hello).pose(at: now) == .working)
    }

    @Test func greetsOnFirstLaunchOrAfterAWeek() {
        #expect(TickDirector.greets(lastSeen: nil, now: now))
        #expect(!TickDirector.greets(lastSeen: now.addingTimeInterval(-6 * 24 * 3600), now: now))
        #expect(TickDirector.greets(lastSeen: now.addingTimeInterval(-7 * 24 * 3600), now: now))
    }

    @Test func idleTickDozesOff() {
        #expect(director(.idle, hour: 23).pose(at: now) == .sleeping)
        #expect(director(.idle, since: 9 * 60).pose(at: now) == .ready)
        #expect(director(.idle, since: 10 * 60).pose(at: now) == .sleeping)
        #expect(director(.idle, since: 0).nextChange(after: now) == now.addingTimeInterval(600))
    }

    @Test func runningSessions() {
        #expect(director(.active(session(.focus))).pose(at: now) == .working)
        #expect(director(.active(session(.focus, paused: true))).pose(at: now) == .waiting)
        #expect(director(.active(session(.rest))).pose(at: now) == .onBreak)
        #expect(director(.active(session(.focus))).nextChange(after: now) == nil)
    }

    @Test func burstsSettleOnTheLast() {
        // The first change shows at once.
        #expect(TickDirector.showTime(for: now, lastShown: nil) == now)
        #expect(TickDirector.showTime(for: now, lastShown: now.addingTimeInterval(-1)) == now)
        // One 0.1 s after the last waits until 0.3 s have passed.
        let last = now.addingTimeInterval(-0.1)
        #expect(TickDirector.showTime(for: now, lastShown: last) == last.addingTimeInterval(0.3))
    }

    @Test func theRingFollowsTheTimer() {
        #expect(TickPose.ringProgress(for: .idle, at: now) == 1)
        // 600 s of 1500 left: the ring drains while focusing...
        #expect(abs(TickPose.ringProgress(for: .active(session(.focus)), at: now) - 0.4) < 0.001)
        // ...and holds when paused...
        #expect(abs(TickPose.ringProgress(for: .active(session(.focus, paused: true)), at: now.addingTimeInterval(500)) - 0.4) < 0.001)
        // ...and fills up through a break.
        #expect(abs(TickPose.ringProgress(for: .active(session(.rest)), at: now) - 0.6) < 0.001)
        #expect(TickPose.ringProgress(for: finished(), at: now) == 0)
        // Stopped early with 10 of 25 minutes done: 60% was left.
        #expect(abs(TickPose.ringProgress(for: finished(.endedEarly, focused: 600), at: now) - 0.6) < 0.001)
    }
}

/// Tick hears the alarm.
@MainActor
struct TickAlarmTests {
    @Test func servicesFollowTheRingingAlarm() {
        let alarm = SpyAlarm()
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   schedulesCompletion: false, liveActivity: SpyLiveActivity(), notifications: SpyNotifier(),
                                   alarm: alarm, appIcon: SpyAppIcon(), widgets: SpyWidgets(), haptics: SpyHaptics(),
                                   announce: { _ in })
        services.watchAlarm()
        #expect(!services.alarmRinging)
        alarm.ring?(true)
        #expect(services.alarmRinging)
        services.stopAlarm()
        #expect(!services.alarmRinging)
        #expect(alarm.calls.last == "cancel")
    }
}
