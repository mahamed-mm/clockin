import Foundation
import Testing
@testable import Clockin

/// A subject's page: facts about every session saved under its name.
struct SubjectHistoryTests {
    let now = Date(timeIntervalSince1970: 1_791_986_400) // A Wednesday at 16:00 in Oslo.

    func session(_ name: String, daysAgo: Double, hour: Int = 9, minutes: Double = 25,
                 planned: Double? = 25) -> SubjectHistory.Session {
        let day = osloCalendar.date(byAdding: .day, value: -Int(daysAgo), to: osloCalendar.startOfDay(for: now))!
        let start = osloCalendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return SubjectHistory.Session(id: UUID(), name: name, startedAt: start,
                                      completedAt: start.addingTimeInterval(minutes * 60), seconds: minutes * 60,
                                      plannedSeconds: planned.map { $0 * 60 })
    }

    @Test func itGathersEverySpellingAndNothingElse() {
        let history = SubjectHistory(key: "chemistry", sessions: [
            session("Chemistry", daysAgo: 3), session(" chemistry ", daysAgo: 1), session("Kjemi", daysAgo: 2),
            session("CHEMISTRY", daysAgo: 10),
        ])
        #expect(history.sessionCount == 3)
        #expect(history.name == " chemistry ", "As the newest session spells it")
        #expect(history.totalSeconds == 75 * 60)
        #expect(history.firstDate == history.sessions.last?.completedAt)
        #expect(history.sessions.map(\.completedAt) == history.sessions.map(\.completedAt).sorted(by: >))
    }

    @Test func accentsAreLettersOfTheirOwn() {
        let history = SubjectHistory(key: SymbolBook.key(for: "Kjemi"), sessions: [
            session("Kjemi", daysAgo: 1), session("Kjémi", daysAgo: 1),
        ])
        #expect(history.sessionCount == 1)
    }

    @Test func theTypicalLengthIsTheMedianToFiveMinutes() {
        let history = SubjectHistory(key: "essay", sessions: [
            session("Essay", daysAgo: 1, minutes: 25), session("Essay", daysAgo: 2, minutes: 50),
            session("Essay", daysAgo: 3, minutes: 23), session("Essay", daysAgo: 4, minutes: 27),
        ])
        #expect(history.typicalLength == TimeInterval(25 * 60))
        let short = SubjectHistory(key: "essay", sessions: [session("Essay", daysAgo: 1, minutes: 1)])
        #expect(short.typicalLength == TimeInterval(5 * 60), "Never under five")
        #expect(SubjectHistory(key: "essay", sessions: []).typicalLength == nil)
    }

    @Test func theUsualTimeOfDayFollowsTheWeeksRule() {
        let mornings = SubjectHistory(key: "essay", sessions: [
            session("Essay", daysAgo: 1, hour: 8), session("Essay", daysAgo: 2, hour: 10),
            session("Essay", daysAgo: 3, hour: 19),
        ])
        #expect(mornings.usualPart(calendar: osloCalendar) == .morning)
        let mixed = SubjectHistory(key: "essay", sessions: [
            session("Essay", daysAgo: 1, hour: 8), session("Essay", daysAgo: 2, hour: 14),
            session("Essay", daysAgo: 3, hour: 19),
        ])
        #expect(mixed.usualPart(calendar: osloCalendar) == nil)
    }

    @Test func itShowsTheLastThreeMonthsDayByDay() {
        let history = SubjectHistory(key: "essay", sessions: [
            session("Essay", daysAgo: 1), session("Essay", daysAgo: 1, hour: 14), session("Essay", daysAgo: 40),
            session("Essay", daysAgo: 200),
        ])
        let months = history.months(endingAt: now, calendar: osloCalendar)
        #expect(months.count == 3)
        #expect(months.last?.month.contains(now) == true)
        #expect(months.map(\.month.start) == months.map(\.month.start).sorted())
        let yesterday = osloCalendar.startOfDay(for: history.sessions[0].completedAt)
        #expect(months.last?.days[yesterday]?.sessions == 2)
        #expect(months.flatMap(\.days.values).map(\.sessions).reduce(0, +) == 3, "200 days back is too far")
    }

    @Test func itKnowsTheRecentOnesAndTheLastPlan() {
        let sessions = (0..<10).map { session("Essay", daysAgo: Double($0), planned: $0 == 0 ? 50 : 25) }
        let history = SubjectHistory(key: "essay", sessions: sessions)
        #expect(history.recent.count == SubjectHistory.recentCount)
        #expect(history.lastPlanned == TimeInterval(50 * 60))
    }

    @Test func factsReadAsSentences() {
        let since = osloCalendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
        #expect(Copy.subjectTotal(seconds: 275 * 60, sessions: 11, since: since) == "4 h 35 min over 11 sessions since 3 August.")
        #expect(Copy.subjectTotalSpoken(seconds: 275 * 60, sessions: 1, since: since)
                == "4 hours, 35 minutes over 1 session since 3 August.")
        #expect(Copy.subjectHabit(part: .morning, length: "25 min") == "Usually in the morning, about 25 min.")
        #expect(Copy.subjectHabit(part: nil, length: "25 min") == "Usually about 25 min.")
    }
}

/// Where a By subject row goes.
struct SubjectRouteTests {
    @Test func aSubjectOpensItsPageAndOtherFilters() {
        #expect(WeekSubjects.route(for: .subject(key: "essay", name: "Essay"), opens: true)?.key == "essay")
        #expect(WeekSubjects.route(for: .other, opens: true) == nil)
        #expect(WeekSubjects.route(for: .subject(key: "essay", name: "Essay"), opens: false) == nil)
    }
}

/// Finding a subject's sessions: every spelling, quickly.
@MainActor
struct SubjectQueryTests {
    @Test func everySpellingIsFoundAndAccentsStayApart() throws {
        let history = HistoryService(container: AppServices.makeEmptyContainer())
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let names = ["Chemistry", " chemistry", "CHEMISTRY ", "Kjemi", "Kjémi"]
        try history.restore(names.enumerated().map { index, name in
            CompletedFocus(id: UUID(), name: name, startedAt: start.addingTimeInterval(Double(index) * 3_600),
                           completedAt: start.addingTimeInterval(Double(index) * 3_600 + 1_500), focusSeconds: 1_500)
        })
        #expect(try history.spellings(of: "chemistry") == ["Chemistry", " chemistry", "CHEMISTRY "])
        #expect(try history.sessions(ofSubject: "chemistry").count == 3)
        #expect(try history.sessions(ofSubject: "kjemi").map(\.name) == ["Kjemi"])
    }

    @Test func fiveThousandSessionsAreQuick() throws {
        let history = HistoryService(container: AppServices.makeEmptyContainer())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try history.restore((0..<5_000).map { index in
            CompletedFocus(id: UUID(), name: ["Chemistry", "Essay", "Piano", "Spanish"][index % 4] + " \(index % 40)",
                           startedAt: start.addingTimeInterval(Double(index) * 3_600),
                           completedAt: start.addingTimeInterval(Double(index) * 3_600 + 1_500), focusSeconds: 1_500)
        })
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try history.sessions(ofSubject: "essay 1") }
        #expect(elapsed < .milliseconds(250), "Took \(elapsed)")
    }
}

/// What a subject's page zooms out of.
struct HistoryRouteTests {
    @Test func itZoomsFromWhereItWasOpenedUnlessMotionIsReduced() {
        let row = SubjectRoute(key: "essay", name: "Essay", zoomFrom: SubjectRoute.rowSource("essay"))
        #expect(row.zoomSource(reduceMotion: false) == SubjectRoute.rowSource("essay"))
        #expect(row.zoomSource(reduceMotion: true) == nil)
        let session = UUID()
        let fromCard = SubjectRoute(key: "essay", name: "Essay", zoomFrom: session)
        #expect(fromCard.zoomSource(reduceMotion: false) == AnyHashable(session))
        // From a ribbon block there's no row to zoom out of.
        #expect(SubjectRoute(key: "essay", name: "Essay").zoomSource(reduceMotion: false) == nil)
    }
}
