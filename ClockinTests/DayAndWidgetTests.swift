import Foundation
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

    @Test func roundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let store = WidgetSnapshotStore(defaults: defaults)
        #expect(store.load() == nil)

        let written = snapshot([afternoon])
        store.save(written)
        #expect(store.load() == written)
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
