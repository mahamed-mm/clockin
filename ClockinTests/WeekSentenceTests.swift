import Foundation
import Testing
@testable import Clockin

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

    /// The demo week on Wednesday 14 October 2026: four sessions, Monday to
    /// Wednesday, two of them on Tuesday.
    private var demoWeek: WeekFacts {
        let sessions = [(12, 9), (13, 10), (13, 14), (14, 20)].map { day, hour in
            let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
            return WeekFacts.Session(startedAt: start, completedAt: start.addingTimeInterval(1_500), seconds: 1_500)
        }
        return WeekFacts(sessions: sessions, calendar: calendar)!
    }

    private func keeps(_ line: String, language: String = "en") -> Bool {
        WeekSentence.keepsToFacts(line, demoWeek, calendar: calendar, language: language)
    }

    @Test func theModelOnlySeesNumbersAndWeekdays() {
        #expect(WeekSentence.prompt(for: facts, calendar: calendar) == """
            Sessions: 3
            Total focus: 75 minutes
            Longest session: 25 minutes
            Days with focus: 1 (Tuesday)
            Busiest day: Tuesday
            Mostly in the morning
            """)
        #expect(WeekSentence.prompt(for: demoWeek, calendar: calendar) == """
            Sessions: 4
            Total focus: 100 minutes
            Longest session: 25 minutes
            Days with focus: 3 (Monday, Tuesday, Wednesday)
            Busiest day: Tuesday
            Spread across the day
            """)
    }

    @Test func aLineNamesOnlyDaysWithFocus() {
        #expect(keeps("Focus on Monday, Tuesday and Wednesday."))
        #expect(keeps("Tuesday was the longest day."))
        #expect(keeps("A calm week, spread across the day."))
        #expect(!keeps("Focus spanned 3 days with sessions on Tuesday, Wednesday, and Friday."))
        #expect(!keeps("Most of it fell on Saturday."))
        #expect(!keeps("Sundays stayed quiet."))
    }

    @Test func aNorwegianLineNamesOnlyDaysWithFocus() {
        #expect(keeps("Fokus på mandag, tirsdag og onsdag.", language: "nb"))
        #expect(keeps("Tirsdagen var den lengste.", language: "nb"))
        #expect(!keeps("Fokus på tirsdag, onsdag og fredag.", language: "nb"))
        #expect(!keeps("Mest fokus på søndag.", language: "nb"))
        // The facts are in English, so an English day slipping through counts too.
        #expect(!keeps("Mest fokus på Friday.", language: "nb"))
    }

    @Test func aLineCountsDaysAndSessionsRight() {
        #expect(keeps("Four sessions across 3 days."))
        #expect(keeps("Focus on three days, mostly Tuesday."))
        #expect(keeps("A 25-minute session started the week."))
        #expect(!keeps("Five sessions across three days."))
        #expect(!keeps("Four sessions over 2 days."))
        #expect(!keeps("3 long sessions this week."))
        #expect(keeps("Fire økter fordelt på tre dager.", language: "nb"))
        #expect(!keeps("Tre fokusøkter denne uka.", language: "nb"))
        #expect(!keeps("Fire økter på to dager.", language: "nb"))
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

    @Test func aLineThatStraysFromTheFactsGivesWayToTheFixedOne() async {
        let wrong = FakeWriter(reply: .success("Focus spanned 3 days with sessions on Tuesday, Wednesday, and Friday."))
        #expect(await WeekSentence.line(for: demoWeek, calendar: calendar, writer: wrong, enabled: true)
            == Copy.weekSentence(demoWeek, calendar: calendar))
        let right = FakeWriter(reply: .success("Four sessions from Monday to Wednesday."))
        #expect(await WeekSentence.line(for: demoWeek, calendar: calendar, writer: right, enabled: true)
            == "Four sessions from Monday to Wednesday.")
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
