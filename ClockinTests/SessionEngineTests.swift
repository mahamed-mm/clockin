import ActivityKit
import Foundation
import SwiftData
import Testing
@testable import Clockin

@MainActor
struct SessionEngineTests {
    let clock = FakeClock()
    let store = InMemorySessionStateStore()
    let log = SpyLog()
    let effects = SpyEffects()

    func makeEngine() -> SessionEngine {
        let engine = SessionEngine(now: { [clock] in clock.now }, calendar: osloCalendar, store: store, log: log,
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

        #expect(engine.stage.completedFocus?.name == "Reading")
        #expect(log.recorded.count == 1)
        #expect(log.recorded.first?.focusSeconds == Durations.duration(for: .focus))
        #expect(effects.events.last == .focusCompleted(.live))
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
        #expect(engine.stage.completedFocus?.name == "Math")
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
        #expect(effects.events.last == .breakFinished(.live))
    }

    @Test func breakMustBeStartedManually() {
        let engine = makeEngine()
        engine.start(name: "Piano")
        clock.advance(Durations.duration(for: .focus) + 3_600)
        engine.reconcile()
        #expect(engine.stage.completedFocus?.name == "Piano")
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

    @Test func pausingAtZeroCompletesInstead() {
        let engine = makeEngine()
        engine.start(name: "Edge")
        clock.advance(Durations.duration(for: .focus))
        engine.pause()

        #expect(engine.stage.completedFocus?.name == "Edge")
        #expect(log.recorded.count == 1)
        #expect(!effects.events.contains(.paused))
    }

    @Test func breakEndFoundLaterIsNotLive() {
        let engine = makeEngine()
        engine.start(name: "Piano")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()
        engine.startBreak()
        clock.advance(Durations.duration(for: .rest) + 3_600)
        engine.reconcile()

        #expect(effects.events.last == .breakFinished(.stale))
    }

    @Test func savingWaitingSessionsIsAnnounced() {
        log.failing = true
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()
        #expect(!effects.events.contains(.historySaved))

        log.failing = false
        engine.reconcile()
        #expect(effects.events.last == .historySaved)
        engine.reconcile()
        #expect(effects.events.filter { $0 == .historySaved }.count == 1)
    }

    @Test func unsavedSessionWaitsAndIsSavedLater() {
        log.failing = true
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()

        #expect(engine.stage.completedFocus?.name == "Essay")
        #expect(log.recorded.isEmpty)
        #expect(store.state.pendingRecords?.map(\.name) == ["Essay"])

        // It survives a relaunch, then lands once the store works again.
        log.failing = false
        let relaunched = makeEngine()
        relaunched.reconcile()
        #expect(log.recorded.map(\.name) == ["Essay"])
        #expect(store.state.pendingRecords == nil)
        #expect(relaunched.stage.completedFocus?.name == "Essay")
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

    // MARK: Old completions

    @Test func completionNoticedSoonStillCountsAsRecent() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus) + 60)
        engine.reconcile()
        #expect(effects.events.last == .focusCompleted(.recent))
    }

    @Test func completionNoticedAfterABreakLengthIsStale() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus) + Durations.duration(for: .rest))
        engine.reconcile()
        #expect(effects.events.last == .focusCompleted(.stale))
    }

    @Test func completionNoticedAfterMidnightIsStale() {
        // Starts 23:33 in Oslo, ends 23:58, and the app looks at 00:01.
        clock.now = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 33))!
        let engine = makeEngine()
        engine.start(name: "Late one")
        clock.advance(Durations.duration(for: .focus) + 180)
        engine.reconcile()
        #expect(effects.events.last == .focusCompleted(.stale))
    }

    @Test func completionKeepsItsDetailsAcrossRelaunch() throws {
        let engine = makeEngine()
        engine.start(name: "Thesis")
        clock.advance(Durations.duration(for: .focus))
        engine.reconcile()

        let focus = try #require(engine.stage.completedFocus)
        #expect(focus.focusSeconds == Durations.duration(for: .focus))
        #expect(focus.completedAt == clock.now)
        #expect(store.state.completedFocus == focus)
        #expect(makeEngine().stage == .focusComplete(focus))
    }

    @Test func undatedCompletionFromAnOlderBuildOpensIdle() {
        store.state = PersistedSessionState(completedFocusName: "Thesis outline", format: nil)
        #expect(makeEngine().stage == .idle)
    }

    // MARK: Clock changes and names

    @Test func settingTheClockBackCannotAddTime() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(-3_600)
        let session = try #require(engine.active)
        #expect(session.remaining(at: clock.now) == Durations.duration(for: .focus))
        #expect(session.progress(at: clock.now) == 0)
    }

    @Test func settingTheClockBackRestartsTheCountdownInsteadOfFreezing() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(-3_600)
        engine.reconcile()

        let session = try #require(engine.active)
        #expect(session.endDate == clock.now.addingTimeInterval(Durations.duration(for: .focus)))
        #expect(effects.events.last == .restored)
        #expect(store.state.active == session)

        clock.advance(60)
        #expect(session.remaining(at: clock.now) == Durations.duration(for: .focus) - 60)
    }

    @Test func longNamesAreCappedForTheLockScreen() {
        let engine = makeEngine()
        engine.start(name: "  " + String(repeating: "a", count: 59) + " " + String(repeating: "b", count: 20))
        // Cut at 60 characters, then the space left at the end is trimmed.
        #expect(engine.active?.name == String(repeating: "a", count: 59))
    }

    @Test func namesAreCappedInBytesToo() throws {
        // Each character carries 20 combining accents: 41 bytes apiece.
        let stacked = "a" + String(repeating: "\u{0301}", count: 20)
        let name = ActiveSession.cleanName(String(repeating: stacked, count: 60))
        #expect(name.utf8.count <= ActiveSession.maxNameBytes)
        #expect(name.count == 5)
    }

    // MARK: Lock Screen button

    @Test func lockScreenButtonOnlyMovesItsOwnSession() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        let id = try #require(engine.active?.id)

        engine.setPaused(true, sessionID: UUID())
        #expect(engine.active?.isPaused == false)

        engine.setPaused(true, sessionID: id)
        engine.setPaused(true, sessionID: id) // A second tap doesn't resume it.
        #expect(engine.active?.isPaused == true)
        #expect(effects.events.filter { $0 == .paused }.count == 1)

        engine.setPaused(false, sessionID: id)
        #expect(engine.active?.isPaused == false)
    }

    // MARK: Undo cancel

    @Test func cancelCanBeUndone() throws {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(600)
        engine.pause()
        let before = try #require(engine.active)
        engine.cancel()
        #expect(engine.undoableCancel == before)

        clock.advance(4)
        engine.undoCancel()
        #expect(engine.active == before)
        #expect(effects.events.last == .restored)
        #expect(engine.undoableCancel == nil)
        #expect(store.state.active == before)
    }

    @Test func undoRunsOut() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        engine.cancel()
        clock.advance(SessionEngine.standardUndoWindow + 1)
        engine.undoCancel()
        #expect(engine.stage == .idle)
    }

    @Test func startingAgainDropsTheUndo() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        engine.cancel()
        engine.start(name: "Other")
        #expect(engine.undoableCancel == nil)
        engine.undoCancel()
        #expect(engine.active?.name == "Other")
    }

    @Test func undoingASessionThatRanOutMeanwhileCompletesIt() {
        let engine = makeEngine()
        engine.start(name: "Essay")
        clock.advance(Durations.duration(for: .focus) - 2)
        engine.cancel()
        clock.advance(4)
        engine.undoCancel()
        #expect(engine.stage.completedFocus?.name == "Essay")
        #expect(log.recorded.count == 1)
        // Straight to complete, without a card for a finished session first.
        #expect(effects.events == [.started, .cancelled, .focusCompleted(.live)])
    }

    @Test func undoWindowCanBeLonger() {
        let engine = makeEngine()
        engine.undoWindow = { 30 }
        engine.start(name: "Essay")
        engine.cancel()
        clock.advance(20)
        engine.undoCancel()
        #expect(engine.active?.name == "Essay")
    }

    @Test func completionWhileClosedIsRecordedOnRelaunch() throws {
        let first = makeEngine()
        first.start(name: "Thesis")
        let end = try #require(first.active?.endDate)
        clock.advance(Durations.duration(for: .focus) + 600)

        let relaunched = makeEngine()
        relaunched.restore()
        #expect(relaunched.stage.completedFocus?.name == "Thesis")
        #expect(log.recorded.count == 1)
        #expect(log.recorded.first?.completedAt == end)
        #expect(effects.events.last == .focusCompleted(.stale))
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

    @Test func waitingSessionsCountOnce() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!
        let saved = UUID()
        let records = [(id: saved, completedAt: now.addingTimeInterval(-3_600), seconds: 1_500.0)]
        let pending = [
            CompletedFocus(id: saved, name: "Also saved", startedAt: now, completedAt: now, focusSeconds: 1_500),
            CompletedFocus(id: UUID(), name: "Waiting", startedAt: now, completedAt: now.addingTimeInterval(-60),
                           focusSeconds: 1_500),
        ]
        let stats = TodayStats.make(records: records, pending: pending, unrecordedActive: nil, now: now,
                                    calendar: calendar)
        #expect(stats.sessionCount == 2)
        #expect(stats.focusMinutes == 50)
    }

    @Test func weekWithAClockChangeStillHasSevenDays() {
        // Clocks go back in Oslo on Sunday 25 October 2026.
        var monday = calendar
        monday.firstWeekday = 2
        let sunday = monday.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let totals = TodayStats.weekTotals(records: [(sunday, 1_500)], containing: sunday, calendar: monday)

        #expect(totals.map { monday.component(.day, from: $0.day) } == [19, 20, 21, 22, 23, 24, 25])
        #expect(totals.allSatisfy { monday.component(.hour, from: $0.day) == 0 })
        #expect(totals[6].sessions == 1)
    }

    @Test func weekCanStartOnSunday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let friday = sundayFirst.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!
        let totals = TodayStats.weekTotals(records: [(friday, 1_500)], containing: friday, calendar: sundayFirst)

        #expect(sundayFirst.component(.weekday, from: totals[0].day) == 1)
        #expect(sundayFirst.component(.day, from: totals[0].day) == 4)
        #expect(totals[5].sessions == 1)
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
        let focus = CompletedFocus(id: UUID(), name: "Read", startedAt: .now, completedAt: .now, focusSeconds: 1_500)
        try log.record(focus)
        try log.record(focus)
        #expect(TodayStats.fetchRecords(on: .now, calendar: .current, context: log.context).count == 1)
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

    @Test func breakPhraseReadsAnyLength() {
        #expect(Durations.breakPhrase(seconds: 300) == "5-minute")
        #expect(Durations.breakPhrase(seconds: 900) == "15-minute")
        #expect(Durations.breakPhrase(seconds: 5) == "5-second")
    }
}

@MainActor
struct LiveActivityTests {
    /// A countdown turns stale at its end date, which is when completion has to find it.
    @Test func staleCountdownStillShowsTheSession() {
        #expect(LiveActivityController.isShowingSession(.active))
        #expect(LiveActivityController.isShowingSession(.stale))
        #expect(!LiveActivityController.isShowingSession(.ended))
        #expect(!LiveActivityController.isShowingSession(.dismissed))
    }
}

@MainActor
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
        #expect(state.breakDuration == nil)
        #expect(state.phase == .focus)
    }
}
