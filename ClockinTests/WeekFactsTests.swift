import Foundation
import Testing
@testable import Clockin

/// The line under History's week strip: what the week came to, in words.
struct WeekFactsTests {
    private let calendar: Calendar = {
        var calendar = osloCalendar
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }()

    /// A session in October 2026: the 12th is a Monday.
    private func session(day: Int, hour: Int, minutes: Double = 25) -> WeekFacts.Session {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        return WeekFacts.Session(startedAt: start, completedAt: start.addingTimeInterval(minutes * 60),
                                 seconds: minutes * 60)
    }

    private func sentence(_ sessions: [WeekFacts.Session]) throws -> String {
        Copy.weekSentence(try #require(WeekFacts(sessions: sessions, calendar: calendar)), calendar: calendar)
    }

    @Test func anEmptyWeekHasNoLine() {
        #expect(WeekFacts(sessions: [], calendar: calendar) == nil)
        #expect(WeekFacts(sessions: [session(day: 12, hour: 9, minutes: 0)], calendar: calendar) == nil)
    }

    @Test func factsCountTheWeek() throws {
        let facts = try #require(WeekFacts(sessions: [session(day: 12, hour: 9), session(day: 13, hour: 10, minutes: 50),
                                                      session(day: 13, hour: 14)], calendar: calendar))
        #expect(facts.sessions == 3)
        #expect(facts.totalSeconds == 100 * 60)
        #expect(facts.longestSeconds == 50 * 60)
        #expect(facts.daysWithFocus == 2)
        #expect(facts.busiestDay == calendar.startOfDay(for: session(day: 13, hour: 0).startedAt))
        #expect(facts.mostlyIn == .morning)
    }

    @Test func partsOfTheDayChangeAtNoonAndFive() {
        let at = { (hour: Int) in WeekFacts.PartOfDay(self.session(day: 12, hour: hour).startedAt, calendar: self.calendar) }
        #expect(at(11) == .morning)
        #expect(at(12) == .afternoon)
        #expect(at(16) == .afternoon)
        #expect(at(17) == .evening)
        #expect(at(2) == .morning)
    }

    @Test func aTieGoesToTheEarlierDay() throws {
        let facts = try #require(WeekFacts(sessions: [session(day: 14, hour: 9), session(day: 12, hour: 9)],
                                           calendar: calendar))
        #expect(facts.busiestDay == calendar.startOfDay(for: session(day: 12, hour: 0).startedAt))
    }

    @Test func theSentenceReadsTheWeek() throws {
        #expect(try sentence([session(day: 13, hour: 9)]) == "One session this week, on Tuesday morning.")
        #expect(try sentence([session(day: 13, hour: 20)]) == "One session this week, on Tuesday evening.")
        #expect(try sentence([session(day: 12, hour: 9), session(day: 13, hour: 10), session(day: 13, hour: 11)])
            == "Mostly mornings this week; Tuesday was your longest day.")
        #expect(try sentence([session(day: 12, hour: 9), session(day: 13, hour: 14), session(day: 14, hour: 20)])
            == "Spread across the day this week; Monday was your longest day.")
        #expect(try sentence([session(day: 15, hour: 14), session(day: 15, hour: 15)])
            == "Mostly afternoons this week, all on Thursday.")
        #expect(try sentence([session(day: 15, hour: 9), session(day: 15, hour: 20)]) == "All on Thursday this week.")
    }
}
