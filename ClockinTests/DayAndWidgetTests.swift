import Foundation
import SwiftData
import Testing
@testable import Clockin

/// Day boundaries on the days the clocks change, where a day isn't 24 hours.
struct DayBoundaryTests {
    @Test func osloFallBackDayHas25Hours() throws {
        // Clocks go back in Oslo on Sunday 25 October 2026.
        let noon = try #require(osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
        let day = osloCalendar.dayRange(containing: noon)
        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 25 * 3_600)
        let next = osloCalendar.dateComponents([.day, .hour, .minute], from: day.upperBound)
        #expect(next.day == 26 && next.hour == 0 && next.minute == 0)
    }

    @Test func newYorkFallBackDayHas25Hours() throws {
        // Clocks go back in New York on Sunday 1 November 2026.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let noon = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let day = newYork.dayRange(containing: noon)
        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 25 * 3_600)
        let next = newYork.dateComponents([.day, .hour, .minute], from: day.upperBound)
        #expect(next.day == 2 && next.hour == 0 && next.minute == 0)
    }

    @Test func springForwardDayHas23Hours() throws {
        // Clocks go forward in Oslo on Sunday 29 March 2026.
        let noon = try #require(osloCalendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let day = osloCalendar.dayRange(containing: noon)
        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 23 * 3_600)
    }

    @Test func freshnessFollowsAgeAndTheDay() throws {
        let afternoon = try #require(osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 14)))
        func freshness(_ end: Date, _ age: TimeInterval) -> Freshness {
            Freshness.of(endedAt: end, now: end.addingTimeInterval(age), recentWindow: 300, calendar: osloCalendar)
        }
        #expect(freshness(afternoon, 1) == .live)
        #expect(freshness(afternoon, 120) == .recent)
        #expect(freshness(afternoon, 300) == .stale)

        let lateNight = try #require(osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9,
                                                                           hour: 23, minute: 58)))
        #expect(freshness(lateNight, 180) == .stale)
    }
}

@MainActor
struct FinishedCopyTests {
    @Test func saysWhenAnOldCompletionFinished() throws {
        let now = try #require(osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15)))
        let earlier = now.addingTimeInterval(-3_600)
        let yesterday = now.addingTimeInterval(-86_400)
        let lastWeek = now.addingTimeInterval(-6 * 86_400)

        #expect(TimeFormat.finished(earlier, now: now, calendar: osloCalendar) == "Finished at \(TimeFormat.time(earlier))")
        #expect(TimeFormat.finished(yesterday, now: now, calendar: osloCalendar)
                == "Finished yesterday at \(TimeFormat.time(yesterday))")
        let date = lastWeek.formatted(.dateTime.month(.abbreviated).day())
        #expect(TimeFormat.finished(lastWeek, now: now, calendar: osloCalendar)
                == "Finished \(date) at \(TimeFormat.time(lastWeek))")
    }
}

/// The Home Screen widget reads the app's snapshot instead of the store.
struct WidgetSnapshotTests {
    let afternoon = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!

    func snapshot(_ completions: [Date]) -> WidgetSnapshot {
        WidgetSnapshot(rows: completions.map { FocusRow(completedAt: $0, seconds: 1_500) }, writtenAt: afternoon)
    }

    @Test func countsTheDaysSessions() {
        let stats = snapshot([afternoon.addingTimeInterval(-3_600), afternoon.addingTimeInterval(-60)])
            .stats(at: afternoon, active: nil, calendar: osloCalendar)
        #expect(stats.sessionCount == 2)
        #expect(stats.focusMinutes == 50)
    }

    @Test func readsZeroAfterMidnight() {
        let afterMidnight = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 0, minute: 1))!
        let stats = snapshot([afternoon]).stats(at: afterMidnight, active: nil, calendar: osloCalendar)
        #expect(stats == .empty)
    }

    @Test func countsFocusThatRanOutWhileTheAppWasSuspended() {
        let finished = ActiveSession(id: UUID(), name: "A", phase: .focus, plannedDuration: 1_500,
                                     focusStartedAt: afternoon.addingTimeInterval(-1_600),
                                     state: .running(endDate: afternoon.addingTimeInterval(-100)))
        let stats = snapshot([afternoon.addingTimeInterval(-3_600)]).stats(at: afternoon, active: finished,
                                                                           calendar: osloCalendar)
        #expect(stats.sessionCount == 2)
    }

    @Test func anOlderSnapshotStillReads() throws {
        let json = #"{"sessions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","completedAt":800000000,"seconds":1500}],"writtenAt":800000000}"#
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(old.week == nil)
        #expect(old.sessions[0].name == nil)
        #expect(old.sessions[0].symbol == nil)
    }

    func totals(_ counts: [Int], from start: Date) -> [DayTotal] {
        counts.enumerated().map { index, count in
            DayTotal(day: osloCalendar.date(byAdding: .day, value: index, to: start)!, seconds: Double(count) * 1_500,
                     sessions: count)
        }
    }

    @Test func theWeekKeepsEarlierDaysAndFollowsToday() {
        let week = osloCalendar.weekInterval(containing: afternoon)
        let written = WidgetSnapshot(
            sessions: [.init(id: UUID(), completedAt: afternoon.addingTimeInterval(-60), seconds: 1_500, name: "A")],
            week: totals([2, 3, 1, 0, 0, 0, 0], from: week.start), writtenAt: afternoon)
        let days = written.week(at: afternoon, active: nil, calendar: osloCalendar)
        #expect(days.count == 7)
        let todayIndex = days.firstIndex { osloCalendar.isDate($0.day, inSameDayAs: afternoon) }!
        #expect(days[todayIndex].sessions == 1) // From the sessions, as of now.
        #expect(days.prefix(todayIndex).map(\.sessions) == Array([2, 3, 1, 0, 0, 0, 0].prefix(todayIndex)))
        #expect(days.suffix(from: todayIndex + 1).allSatisfy { $0.sessions == 0 })
    }

    @Test func aNewWeekStartsEmptyWithoutTheApp() {
        let week = osloCalendar.weekInterval(containing: afternoon)
        let written = WidgetSnapshot(sessions: [], week: totals([4, 4, 4, 4, 4, 4, 4], from: week.start),
                                     writtenAt: afternoon)
        let nextWeek = osloCalendar.date(byAdding: .day, value: 7, to: afternoon)!
        let days = written.week(at: nextWeek, active: nil, calendar: osloCalendar)
        #expect(days.allSatisfy { $0.sessions == 0 })
        #expect(days.contains { osloCalendar.isDate($0.day, inSameDayAs: nextWeek) })
    }

    @Test func todaysListIsNewestFirstAndOnlyToday() {
        let written = WidgetSnapshot(sessions: [
            .init(id: UUID(), completedAt: afternoon.addingTimeInterval(-7_200), seconds: 1_500, name: "Old"),
            .init(id: UUID(), completedAt: afternoon.addingTimeInterval(-60), seconds: 1_500, name: "New"),
        ], week: nil, writtenAt: afternoon)
        #expect(written.sessions(on: afternoon, calendar: osloCalendar).map(\.name) == ["New", "Old"])
        let tomorrow = osloCalendar.date(byAdding: .day, value: 1, to: afternoon)!
        #expect(written.sessions(on: tomorrow, calendar: osloCalendar).isEmpty)
    }

    @Test func roundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let store = WidgetSnapshotStore(defaults: defaults)
        #expect(store.load() == nil)

        let written = snapshot([afternoon])
        store.save(written)
        #expect(store.load() == written)
    }
}

/// When the widget redraws on its own: Tick sleeps at 22:00 and wakes at
/// 06:00, and a running session adds only its end.
struct WidgetTimelineTests {
    func at(day: Int = 9, _ hour: Int, _ minute: Int = 0) -> Date {
        osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func session(_ state: ActiveSession.RunState, from now: Date) -> ActiveSession {
        ActiveSession(id: UUID(), name: "A", phase: .focus, plannedDuration: 1_500,
                      focusStartedAt: now.addingTimeInterval(-60), state: state)
    }

    func dates(at now: Date, active: ActiveSession? = nil, shift: TimeInterval = 0) -> [Date] {
        WidgetSnapshot.timelineDates(at: now, active: active, calendar: osloCalendar, shift: shift)
    }

    @Test func anIdleEveningRedrawsWhenNightStarts() {
        #expect(dates(at: at(15)) == [at(15), at(22), at(day: 10, 0)])
    }

    @Test func anIdleSmallHourRedrawsWhenNightEndsAndStarts() {
        #expect(dates(at: at(1, 30)) == [at(1, 30), at(6), at(22), at(day: 10, 0)])
    }

    @Test func lateAtNightOnlyMidnightIsLeft() {
        #expect(dates(at: at(23, 10)) == [at(23, 10), at(day: 10, 0)])
    }

    @Test func aRunningSessionAddsOnlyItsEnd() {
        let running = session(.running(endDate: at(21, 50) + 300), from: at(21, 50))
        #expect(dates(at: at(21, 50), active: running) == [at(21, 50), at(21, 55), at(day: 10, 0)])
        let paused = session(.paused(remaining: 600), from: at(21, 50))
        #expect(dates(at: at(21, 50), active: paused) == [at(21, 50), at(day: 10, 0)])
    }

    @Test func aSessionThatAlreadyRanOutCountsAsIdle() {
        let finished = session(.running(endDate: at(21, 40)), from: at(21, 50))
        #expect(dates(at: at(21, 50), active: finished) == [at(21, 50), at(22), at(day: 10, 0)])
    }

    @Test func theDemoClockMovesNight() {
        // Shown as 21:00 at 15:00: night starts an hour from now, and ends at midnight, with the next timeline.
        #expect(dates(at: at(15), shift: 6 * 3600) == [at(15), at(16), at(day: 10, 0)])
    }
}

/// What fills a session pill: everything except a session finished early
/// before half its plan. Its minutes always count.
struct FullSessionTests {
    let now = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!

    @Test func onlyAnEarlyFinishUnderHalfIsLeftOut() {
        #expect(FocusRow.isFull(outcome: .completed, seconds: 1_500, planned: 1_500))
        #expect(FocusRow.isFull(outcome: .completed, seconds: 300, planned: nil))
        #expect(FocusRow.isFull(outcome: .endedEarly, seconds: 750, planned: 1_500))
        #expect(!FocusRow.isFull(outcome: .endedEarly, seconds: 749, planned: 1_500))
        #expect(FocusRow.isFull(outcome: .endedEarly, seconds: 60, planned: nil))
    }

    @Test func shortSessionsAddMinutesButNoPill() {
        let rows = [FocusRow(completedAt: now, seconds: 1_500),
                    FocusRow(completedAt: now, seconds: 300, countsAsFull: false)]
        let stats = TodayStats.make(records: rows, unrecordedActive: nil, now: now, calendar: osloCalendar)
        #expect(stats.sessionCount == 1)
        #expect(stats.focusMinutes == 30)
        let week = TodayStats.weekTotals(records: rows, containing: now, calendar: osloCalendar)
        #expect(week.reduce(0) { $0 + $1.sessions } == 1)
    }

    @Test func aSnapshotFromBeforeEarlyFinishesCountsEverySession() throws {
        let json = #"{"sessions":[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","completedAt":813340800,"seconds":1500}],"writtenAt":813340800}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.rows.map(\.countsAsFull) == [true])
    }

    @Test func aSnapshotKeepsWhichSessionsWereFull() throws {
        let snapshot = WidgetSnapshot(rows: [FocusRow(completedAt: now, seconds: 300, countsAsFull: false)], writtenAt: now)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.stats(at: now, active: nil, calendar: osloCalendar).sessionCount == 0)
    }
}

/// History pages a week at a time, and every week can be reached.
@MainActor
struct HistoryWeekTests {
    func at(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        osloCalendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func weeksFollowTheCalendarsFirstWeekday() {
        var monday = osloCalendar
        monday.firstWeekday = 2
        var sunday = osloCalendar
        sunday.firstWeekday = 1
        let friday = at(10, 9, 15)
        #expect(monday.weekInterval(containing: friday).start == at(10, 5, 0))
        #expect(sunday.weekInterval(containing: friday).start == at(10, 4, 0))
    }

    @Test func aWeekWithTheClocksGoingBackIsOneHourLonger() {
        var monday = osloCalendar
        monday.firstWeekday = 2
        // Oslo leaves summer time on Sunday 25 October 2026.
        let week = monday.weekInterval(containing: at(10, 21, 12))
        #expect(week.duration == 7 * 86_400 + 3_600)
        #expect(week.end == at(10, 26, 0))
    }

    @Test func aWeeksQueryFindsOnlyThatWeek() throws {
        let container = try SharedStore.makeModelContainer(inMemory: true)
        let log = SwiftDataFocusLog(container: container)
        for date in [at(10, 4, 23), at(10, 5, 9), at(10, 11, 22), at(10, 12, 0)] {
            try log.record(CompletedFocus(id: UUID(), name: "S", startedAt: date.addingTimeInterval(-1_500),
                                          completedAt: date, focusSeconds: 1_500))
        }
        var monday = osloCalendar
        monday.firstWeekday = 2
        let week = monday.weekInterval(containing: at(10, 7, 12))
        let found = try log.context.fetch(FetchDescriptor(predicate: FocusRecord.completed(in: week)))
        #expect(Set(found.map(\.completedAt)) == [at(10, 5, 9), at(10, 11, 22)])
    }

    @Test func sessionsWaitingToBeSavedCountInTheirWeekOnly() {
        var monday = osloCalendar
        monday.firstWeekday = 2
        let waiting = [
            CompletedFocus(id: UUID(), name: "This week", startedAt: at(10, 6, 9), completedAt: at(10, 6, 9),
                           focusSeconds: 1_500),
            CompletedFocus(id: UUID(), name: "Last week", startedAt: at(9, 30, 9), completedAt: at(9, 30, 9),
                           focusSeconds: 1_500),
        ]
        let totals = TodayStats.weekTotals(saved: [FocusRow(completedAt: at(10, 5, 9), seconds: 1_500)],
                                           pending: waiting, containing: at(10, 7, 12), calendar: monday)
        #expect(totals.map(\.sessions) == [1, 1, 0, 0, 0, 0, 0])
    }
}

struct DateIntervalTests {
    @Test func backToBackWeeksShareNoMoment() {
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let lastWeek = DateInterval(start: monday.addingTimeInterval(-7 * 86_400), end: monday)
        #expect(!lastWeek.includes(monday))
        #expect(lastWeek.includes(monday.addingTimeInterval(-1)))
        #expect(lastWeek.includes(lastWeek.start))
    }
}

/// Every timer outside the app shows time left, draining.
struct TimerReadingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ state: ActiveSession.RunState, planned: TimeInterval = 1_500) -> ActiveSession {
        ActiveSession(id: UUID(), name: "Essay", phase: .focus, plannedDuration: planned, focusStartedAt: now,
                      state: state)
    }

    @Test func aRunningTimerDrainsFromItsFullLength() {
        let end = now.addingTimeInterval(600)
        #expect(TimerReading(session: session(.running(endDate: end)), at: now)
                == .running(end.addingTimeInterval(-1_500)...end))
    }

    @Test func aPausedTimerShowsTheShareLeft() {
        #expect(TimerReading(session: session(.paused(remaining: 375)), at: now)
                == .paused(fraction: 0.25, remaining: 375))
    }

    @Test func aTimerThatRanOutIsDone() {
        #expect(TimerReading(session: session(.running(endDate: now.addingTimeInterval(-1))), at: now) == .done)
    }

    @Test func minutesAddedLengthenTheWholeRing() {
        // +5 min on a 25-minute session with 100 s left: 400 s of 1 800.
        let end = now.addingTimeInterval(400)
        let extended = session(.running(endDate: end), planned: 1_800)
        #expect(TimerReading(session: extended, at: now) == .running(end.addingTimeInterval(-1_800)...end))
        let state = FocusActivityAttributes.ContentState(session: session(.paused(remaining: 400), planned: 1_800))
        #expect(TimerReading(state: state, done: false) == .paused(fraction: 400.0 / 1_800, remaining: 400))
    }

    @Test func theLockScreenReadsTheSameAsTheApp() {
        let end = now.addingTimeInterval(600)
        let state = FocusActivityAttributes.ContentState(session: session(.running(endDate: end)))
        #expect(TimerReading(state: state, done: false) == .running(state.timerRange))
        #expect(TimerReading(state: state, done: true) == .done)
    }
}
