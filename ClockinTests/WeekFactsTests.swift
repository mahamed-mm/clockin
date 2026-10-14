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

/// The on-device model's line is optional, checked, and only ever sees numbers.
struct WeekSentenceTests {
    private struct FakeWriter: WeekSentenceWriting {
        var isAvailable = true
        var reply: Result<String, Error> = .success("A quiet week, mostly mornings.")
        func write(prompt: String, instructions: String) async throws -> String {
            // Asked for Norwegian, it answers in Norwegian.
            instructions.contains("Norwegian") ? "En rolig uke, mest morgener." : try reply.get()
        }
    }

    private struct Unavailable: Error {}

    private let calendar: Calendar = {
        var calendar = osloCalendar
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private var facts: WeekFacts {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
        let sessions = [0, 1, 2].map { i in
            WeekFacts.Session(startedAt: start.addingTimeInterval(Double(i) * 3_600),
                              completedAt: start.addingTimeInterval(Double(i) * 3_600 + 1_500), seconds: 1_500)
        }
        return WeekFacts(sessions: sessions, calendar: calendar)!
    }

    @Test func theModelOnlySeesNumbersAndADay() {
        #expect(WeekSentence.prompt(for: facts, calendar: calendar) == """
            Sessions: 3
            Total focus: 75 minutes
            Longest session: 25 minutes
            Days with focus: 1
            Busiest day: Tuesday
            Mostly in the morning
            """)
    }

    @Test func onlyOneShortCalmSentenceIsKept() {
        #expect(WeekSentence.validate("A quiet week, mostly mornings.") == "A quiet week, mostly mornings.")
        #expect(WeekSentence.validate("  \"mostly mornings this week\" ") == "Mostly mornings this week.")
        #expect(WeekSentence.validate("") == nil)
        #expect(WeekSentence.validate("Great job!") == nil)
        #expect(WeekSentence.validate("Mornings. Tuesday was long.") == nil)
        #expect(WeekSentence.validate("Why not try evenings?") == nil)
        #expect(WeekSentence.validate("Line one\nline two") == nil)
        #expect(WeekSentence.validate(String(repeating: "word ", count: 30)) == nil)
    }

    @Test func theFixedSentenceStandsInWhenTheModelCant() async {
        let fixed = Copy.weekSentence(facts, calendar: calendar)
        #expect(await WeekSentence.line(for: facts, calendar: calendar, writer: FakeWriter(), enabled: true)
            == "A quiet week, mostly mornings.")
        #expect(await WeekSentence.line(for: facts, calendar: calendar, writer: FakeWriter(), enabled: false) == fixed)
        #expect(await WeekSentence.line(for: facts, calendar: calendar, writer: FakeWriter(isAvailable: false),
                                        enabled: true) == fixed)
        #expect(await WeekSentence.line(for: facts, calendar: calendar,
                                        writer: FakeWriter(reply: .failure(Unavailable())), enabled: true) == fixed)
        #expect(await WeekSentence.line(for: facts, calendar: calendar,
                                        writer: FakeWriter(reply: .success("Amazing work!!")), enabled: true) == fixed)
    }

    @Test func aNorwegianAppGetsANorwegianLine() async {
        #expect(WeekSentence.instructions(language: "nb").hasSuffix("Write the sentence in Norwegian Bokmål."))
        #expect(WeekSentence.instructions(language: "en") == WeekSentence.instructions)
        let line = await WeekSentence.line(for: facts, calendar: calendar, writer: FakeWriter(), enabled: true,
                                           language: "nb", recognize: { _ in "nb" })
        #expect(line == "En rolig uke, mest morgener.")
        // A line that comes back in another language gives way to the fixed one.
        let fixed = Copy.weekSentence(facts, calendar: calendar)
        let english = await WeekSentence.line(for: facts, calendar: calendar, writer: FakeWriter(), enabled: true,
                                              language: "nb", recognize: { _ in "en" })
        #expect(english == fixed)
    }
}
