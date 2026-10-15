import Foundation
import Testing
@testable import Clockin

/// What the Lock Screen widgets say.
struct LockScreenLineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let today = TodayStats(focusSeconds: 69 * 60, sessionCount: 2)

    func session(_ phase: SessionPhase = .focus, name: String = "Chemistry", state: ActiveSession.RunState)
        -> ActiveSession {
        ActiveSession(id: UUID(), name: name, phase: phase, plannedDuration: 1_500,
                      focusStartedAt: now.addingTimeInterval(-600), state: state)
    }

    @Test func withNothingRunningItsToday() {
        #expect(LockScreenLine(stats: today, active: nil, symbol: "flask.fill", at: now)
                == .today(seconds: 69 * 60, sessions: 2))
        #expect(Copy.focusedToday(seconds: 69 * 60).hasSuffix(" today"))
    }

    @Test func aRunningSessionShowsItsNameSymbolAndEnd() {
        let end = now.addingTimeInterval(750)
        let line = LockScreenLine(stats: today, active: session(state: .running(endDate: end)), symbol: "flask.fill",
                                  at: now)
        #expect(line == .running(name: "Chemistry", symbol: "flask.fill", phase: .focus, end: end))
        #expect(line.pose(hour: 12) == .working)
    }

    @Test func pausedAndUnnamed() {
        let line = LockScreenLine(stats: today, active: session(name: "", state: .paused(remaining: 600)),
                                  symbol: SymbolCatalog.unnamed, at: now)
        #expect(line == .paused(name: Copy.displayName(""), symbol: SymbolCatalog.unnamed, phase: .focus))
        #expect(line.pose(hour: 12) == .waiting)
    }

    @Test func aBreakSaysBreakWithTheCup() {
        let end = now.addingTimeInterval(120)
        let line = LockScreenLine(stats: today, active: session(.rest, state: .running(endDate: end)),
                                  symbol: "flask.fill", at: now)
        #expect(line == .running(name: Copy.rest, symbol: "cup.and.saucer.fill", phase: .rest, end: end))
        #expect(line.pose(hour: 12) == .onBreak)
    }

    @Test func aBreakSaysHowItsSpent() {
        let end = now.addingTimeInterval(120)
        func name(_ style: BreakStyle?, long: Bool = false, paused: Bool = false) -> String? {
            var rest = session(.rest, state: paused ? .paused(remaining: 60) : .running(endDate: end))
            rest.breakStyle = style
            rest.isLongBreak = long ? true : nil
            switch LockScreenLine(stats: today, active: rest, symbol: "flask.fill", at: now) {
            case .running(let name, _, _, _), .paused(let name, _, _): return name
            case .today: return nil
            }
        }
        #expect(name(.rest) == "Break")
        #expect(name(.stretch) == "Break · Stretch")
        #expect(name(.breathe, paused: true) == "Break · Breathe")
        #expect(name(.stretch, long: true) == "Long break · Stretch")
        #expect(name(nil, long: true) == "Long break")
    }

    @Test func aSessionThatRanOutIsTodayAgain() {
        let line = LockScreenLine(stats: today, active: session(state: .running(endDate: now.addingTimeInterval(-1))),
                                  symbol: "flask.fill", at: now)
        #expect(line == .today(seconds: 69 * 60, sessions: 2))
    }
}
