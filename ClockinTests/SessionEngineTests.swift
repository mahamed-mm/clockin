import ActivityKit
import Foundation
import SwiftData
import Testing
@testable import Clockin

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class SpyLog: FocusLogging {
    var recorded: [(id: UUID, name: String, seconds: TimeInterval, completedAt: Date)] = []

    func record(id: UUID, name: String, startedAt: Date, completedAt: Date, focusSeconds: TimeInterval) {
        guard !recorded.contains(where: { $0.id == id }) else { return }
        recorded.append((id, name, focusSeconds, completedAt))
    }

    func records(on day: Date, calendar: Calendar) -> [FocusRecord] { [] }
}

@MainActor
final class SpyEffects: SessionEffects {
    var events: [SessionEvent] = []
    func sessionEngine(_ engine: SessionEngine, didEmit event: SessionEvent) { events.append(event) }
}

@MainActor
struct SessionEngineTests {
    let clock = FakeClock()
    let store = InMemorySessionStateStore()
    let log = SpyLog()
    let effects = SpyEffects()

    func makeEngine() -> SessionEngine {
        let engine = SessionEngine(now: { [clock] in clock.now }, store: store, log: log,
                                   schedulesCompletion: false)
        engine.effects = effects
        return engine
    }

    @Test func focusCompletesAndIsRecordedOnce() {
        let engine = makeEngine()
        #expect(engine.start(name: "  Reading  "))
        #expect(engine.active?.name == "Reading")

        clock.advance(Durations.duration(for: .focus) + 1)
        engine.reconcile()
        engine.reconcile()

        #expect(engine.stage == .focusComplete(name: "Reading"))
        #expect(log.recorded.count == 1)
        #expect(log.recorded.first?.seconds == Durations.duration(for: .focus))
        #expect(effects.events.last == .focusCompleted(live: true))
    }

    @Test func emptyNameFallsBackToFocus() {
        let engine = makeEngine()
        engine.start(name: "   ")
        #expect(engine.active?.name == "Focus")
    }

    @Test func onlyOneSessionCanBeActive() {
        let engine = makeEngine()
        #expect(engine.start(name: "A"))
        #expect(!engine.start(name: "B"))
        #expect(engine.active?.name == "A")
    }

    @Test func cancelRecordsNothing() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(600)
        engine.pause()
        engine.cancel()
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()

        #expect(engine.stage == .idle)
        #expect(log.recorded.isEmpty)
        #expect(store.state == PersistedSessionState())
    }

    @Test func pauseFreezesRemainingTime() throws {
        let engine = makeEngine()
        engine.start(name: "Math")
        clock.advance(300)
        engine.pause()
        let frozen = try #require(engine.active).remaining(at: clock.now)

        clock.advance(3_600)
        engine.reconcile()
        #expect(try #require(engine.active).remaining(at: clock.now) == frozen)
        #expect(log.recorded.isEmpty)

        engine.resume()
        clock.advance(frozen - 1)
        engine.reconcile()
        #expect(engine.active != nil)
        clock.advance(2)
        engine.reconcile()
        #expect(engine.stage == .focusComplete(name: "Math"))
    }

    @Test func breakTimeIsNeverRecorded() {
        let engine = makeEngine()
        engine.start(name: "Piano")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()
        engine.startBreak()
        #expect(engine.active?.phase == .rest)
        #expect(engine.active?.plannedDuration == Durations.duration(for: .rest))

        clock.advance(Durations.duration(for: .rest))
        engine.reconcile()
        #expect(engine.stage == .idle)
        #expect(log.recorded.count == 1)
        #expect(effects.events.last == .breakFinished)
    }

    @Test func breakMustBeStartedManually() {
        let engine = makeEngine()
        engine.start(name: "Piano")
        clock.advance(Durations.duration(for: .focus) + 3_600)
        engine.reconcile()
        #expect(engine.stage == .focusComplete(name: "Piano"))
    }

    @Test func cancelDoesNotApplyToBreaks() {
        let engine = makeEngine()
        engine.start(name: "X")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()
        engine.startBreak()
        engine.cancel()
        #expect(engine.active?.phase == .rest)
        engine.skipBreak()
        #expect(engine.stage == .idle)
    }

    @Test func dismissingACompletionIsAnEvent() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()
        engine.skipBreak()

        #expect(engine.stage == .idle)
        #expect(effects.events.last == .completionDismissed)
        #expect(store.state == PersistedSessionState())
    }

    @Test func restoresRunningTimerAfterRelaunch() throws {
        let first = makeEngine()
        first.start(name: "Thesis")
        clock.advance(120)

        let relaunched = makeEngine()
        let session = try #require(relaunched.active)
        #expect(session.name == "Thesis")
        #expect(session.remaining(at: clock.now) == Durations.duration(for: .focus) - 120)
    }

    @Test func completionWhileClosedIsRecordedOnRelaunch() throws {
        let first = makeEngine()
        first.start(name: "Thesis")
        let end = try #require(first.active?.endDate)
        clock.advance(Durations.duration(for: .focus) + 600)

        let relaunched = makeEngine()
        relaunched.restore()
        #expect(relaunched.stage == .focusComplete(name: "Thesis"))
        #expect(log.recorded.count == 1)
        #expect(log.recorded.first?.completedAt == end)
        #expect(effects.events.last == .focusCompleted(live: false))
    }
}

@MainActor
struct TodayStatsTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return c
    }()

    @Test func countsOnlyToday() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let stats = TodayStats.make(records: [
            (UUID(), now.addingTimeInterval(-3_600), 1_500),
            (UUID(), now.addingTimeInterval(-60), 1_500),
            (UUID(), yesterday, 1_500),
        ], unrecordedActive: nil, now: now, calendar: calendar)
        #expect(stats.sessionCount == 2)
        #expect(stats.focusMinutes == 50)
    }

    @Test func resetsAtMidnight() {
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 50))!
        let afterMidnight = lateNight.addingTimeInterval(20 * 60)
        let records = [(id: UUID(), completedAt: lateNight, seconds: 1_500.0)]
        #expect(TodayStats.make(records: records, unrecordedActive: nil, now: lateNight, calendar: calendar).focusMinutes == 25)
        #expect(TodayStats.make(records: records, unrecordedActive: nil, now: afterMidnight, calendar: calendar) == .empty)
    }

    @Test func includesFinishedButUnrecordedFocus() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        let finished = ActiveSession(id: UUID(), name: "A", phase: .focus, plannedDuration: 1_500,
                                     focusStartedAt: now.addingTimeInterval(-1_600),
                                     state: .running(endDate: now.addingTimeInterval(-100)))
        let stillRunning = ActiveSession(id: UUID(), name: "B", phase: .focus, plannedDuration: 1_500,
                                         focusStartedAt: now, state: .running(endDate: now.addingTimeInterval(100)))
        let aBreak = ActiveSession(id: UUID(), name: "C", phase: .rest, plannedDuration: 300,
                                   focusStartedAt: now, state: .running(endDate: now.addingTimeInterval(-1)))
        #expect(TodayStats.make(records: [], unrecordedActive: finished, now: now, calendar: calendar).sessionCount == 1)
        #expect(TodayStats.make(records: [], unrecordedActive: stillRunning, now: now, calendar: calendar) == .empty)
        #expect(TodayStats.make(records: [], unrecordedActive: aBreak, now: now, calendar: calendar) == .empty)
    }
}

@MainActor
struct PersistenceTests {
    @Test func swiftDataLogIsIdempotent() throws {
        let container = try SharedStore.makeModelContainer(inMemory: true)
        let log = SwiftDataFocusLog(container: container)
        let id = UUID()
        log.record(id: id, name: "Read", startedAt: .now, completedAt: .now, focusSeconds: 1_500)
        log.record(id: id, name: "Read", startedAt: .now, completedAt: .now, focusSeconds: 1_500)
        #expect(log.records(on: .now, calendar: .current).count == 1)
    }

    @Test func sessionStateRoundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let store = DefaultsSessionStateStore(defaults: defaults)
        let session = ActiveSession(id: UUID(), name: "Paused one", phase: .focus, plannedDuration: 1_500,
                                    focusStartedAt: .now, state: .paused(remaining: 432))
        store.save(PersistedSessionState(active: session))
        #expect(store.load().active == session)
    }
}

@MainActor
struct RedesignFormattingTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    @Test func weekTotalsSumEachDayMondayFirst() {
        // Friday 9 Oct 2026
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let lastSunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!
        let totals = TodayStats.weekTotals(records: [
            (friday, 1_500), (friday.addingTimeInterval(-3_600), 1_500),
            (monday, 1_500), (lastSunday, 1_500),
        ], containing: friday, calendar: calendar)

        #expect(totals.count == 7)
        #expect(calendar.component(.weekday, from: totals[0].day) == 2)
        #expect(totals[0].seconds == 1_500)
        #expect(totals[4].seconds == 3_000)
        #expect(totals[4].sessions == 2)
        #expect(totals[0].sessions == 1)
        #expect(totals[1].sessions == 0)
        #expect(totals.reduce(0) { $0 + $1.seconds } == 4_500)
    }

    @Test func durationReadsNaturally() {
        #expect(TimeFormat.duration(0) == "0 min")
        #expect(TimeFormat.duration(25 * 60) == "25 min")
        #expect(TimeFormat.duration(75 * 60) == "1 h 15 min")
        #expect(TimeFormat.duration(120 * 60) == "2 h")
    }

    @Test func rangeJoinsStartAndEnd() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(1_500)
        #expect(TimeFormat.range(start, end) == "\(TimeFormat.time(start)) → \(TimeFormat.time(end))")
    }
}

@MainActor
struct MotionTests {
    @Test func animationsRunAtNormalSpeedUnlessSlowMotionIsOn() {
        let settings = DevSettings.shared
        let original = settings.slowAnimations
        defer { settings.slowAnimations = original }

        settings.slowAnimations = false
        #expect(Motion.speed == 1)
        settings.slowAnimations = true
        #expect(Motion.speed == 4)
    }
}

@MainActor
struct EndCopyTests {
    @Test func breakPhraseFollowsTheBreakLength() {
        let settings = DevSettings.shared
        let original = settings.shortTimers
        defer { settings.shortTimers = original }

        settings.shortTimers = false
        #expect(Durations.breakLengthPhrase == "5-minute")
        settings.shortTimers = true
        #expect(Durations.breakLengthPhrase == "5-second")
    }
}

struct LiveActivityTests {
    /// A countdown turns stale at its end date, which is when completion has to find it.
    @Test func staleCountdownStillShowsTheSession() {
        #expect(LiveActivityController.isShowingSession(.active))
        #expect(LiveActivityController.isShowingSession(.stale))
        #expect(!LiveActivityController.isShowingSession(.ended))
        #expect(!LiveActivityController.isShowingSession(.dismissed))
    }
}

struct SessionPillsTests {
    @Test func firstFocusSessionIsOutlined() {
        #expect(SessionPills.state(index: 0, completed: 0, inProgress: true) == .current)
        #expect(SessionPills.state(index: 1, completed: 0, inProgress: true) == .empty)
    }

    @Test func breaksDoNotShowACurrentPill() {
        #expect(SessionPills.state(index: 0, completed: 2, inProgress: false) == .filled(colorIndex: 0))
        #expect(SessionPills.state(index: 1, completed: 2, inProgress: false) == .filled(colorIndex: 1))
        #expect(SessionPills.state(index: 2, completed: 2, inProgress: false) == .empty)
    }

    @Test func moreThanFourFillsTheSetAndCountsExtra() {
        for index in 0..<SessionPills.setSize {
            #expect(SessionPills.state(index: index, completed: 5, inProgress: true) == .filled(colorIndex: index))
        }
        #expect(SessionPills.extra(completed: 5) == 1)
        #expect(SessionPills.caption(completed: 5) == "4 of 4 · +1")
        #expect(SessionPills.caption(completed: 2) == "2 of 4 today")
    }

    @Test func contentStateFromOlderBuildsStillDecodes() throws {
        let json = #"{"phase":"focus","endDate":800000000,"plannedDuration":1500}"#
        let state = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.completedToday == nil)
        #expect(state.phase == .focus)
    }
}
