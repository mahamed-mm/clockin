import Foundation
import Testing
@testable import Clockin

/// The week's minutes by name.
struct SubjectTotalsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ name: String, minutes: Double, at hour: Double = 0) -> SubjectTotals.Session {
        SubjectTotals.Session(name: name, completedAt: start.addingTimeInterval(hour * 3_600), seconds: minutes * 60)
    }

    @Test func namesGroupIgnoringCaseAndShowTheirLatestSpelling() {
        let totals = SubjectTotals([session("chemistry", minutes: 25, at: 1), session("Chemistry ", minutes: 50, at: 2),
                                    session("Spanish", minutes: 25)])
        let expected: [SubjectTotals.Subject] = [
            SubjectTotals.Subject(key: "chemistry", name: "Chemistry ", seconds: 4_500),
            SubjectTotals.Subject(key: "spanish", name: "Spanish", seconds: 1_500),
        ]
        #expect(totals.top == expected)
        #expect(totals.other == nil)
    }

    @Test func unnamedSessionsGroupTogether() {
        let totals = SubjectTotals([session("", minutes: 25), session("  ", minutes: 25)])
        #expect(totals.top.count == 1)
        #expect(totals.top[0].seconds == 50 * 60)
    }

    @Test func tiesGoInNameOrder() {
        let totals = SubjectTotals([session("Spanish", minutes: 25), session("Art", minutes: 25)])
        #expect(totals.top.map(\.name) == ["Art", "Spanish"])
    }

    @Test func theRestGoUnderOtherAndNothingIsLost() {
        let names = ["A", "B", "C", "D", "E", "F"]
        let sessions = names.enumerated().map { session($1, minutes: Double(60 - $0 * 5)) }
        let totals = SubjectTotals(sessions)
        #expect(totals.top.map(\.name) == ["A", "B", "C", "D"])
        #expect(totals.other == 4_500) // 40 and 35 minutes.
        let sum = totals.top.reduce(0) { $0 + $1.seconds } + (totals.other ?? 0)
        #expect(sum == sessions.reduce(0) { $0 + $1.seconds })
    }

    @Test func anEmptyWeekHasNoSubjects() {
        #expect(SubjectTotals([]).top.isEmpty)
    }

    // MARK: Picking a subject

    var week: [SubjectTotals.Session] {
        ["Chemistry", "Spanish", "Piano", "Thesis", "Emails", "Reading"].enumerated().map {
            session($1, minutes: Double(60 - $0 * 5), at: Double($0))
        } + [session("", minutes: 10, at: 30)]
    }

    @Test func aSubjectMatchesItsNameHoweverItIsSpelled() {
        let totals = SubjectTotals(week)
        let chemistry = SubjectFilter.subject(key: SymbolBook.key(for: "Chemistry"), name: "Chemistry")
        #expect(chemistry.matches("Chemistry", in: totals))
        #expect(chemistry.matches("  chemistry ", in: totals))
        #expect(chemistry.matches("CHEMISTRY", in: totals))
        #expect(!chemistry.matches("Chemistry 2", in: totals))
        #expect(!chemistry.matches("", in: totals))
        #expect(chemistry.title == "Chemistry")
    }

    @Test func otherMatchesOnlyTheNamesPastTheTopFour() {
        let totals = SubjectTotals(week)
        #expect(totals.top.map(\.name) == ["Chemistry", "Spanish", "Piano", "Thesis"])
        for name in ["Chemistry", "spanish", "Piano", "Thesis"] {
            #expect(!SubjectFilter.other.matches(name, in: totals))
        }
        for name in ["Emails", "Reading", ""] {
            #expect(SubjectFilter.other.matches(name, in: totals))
        }
    }

    @Test func otherIsWorkedOutForEachWeek() {
        // A week where Emails made the top four: it's no longer "Other".
        let busy = SubjectTotals([session("Emails", minutes: 90), session("Chemistry", minutes: 10),
                                  session("Spanish", minutes: 5), session("Piano", minutes: 5),
                                  session("Thesis", minutes: 1)])
        #expect(!SubjectFilter.other.matches("Emails", in: busy))
        #expect(SubjectFilter.other.matches("Thesis", in: busy))
        #expect(SubjectFilter.other.matches("Emails", in: SubjectTotals(week)))
    }

    @Test func theSameRowIsTheSameChoiceInAnyWeek() {
        let picked = SubjectFilter.subject(key: "chemistry", name: "chemistry")
        let later = SubjectFilter.subject(key: "chemistry", name: "Chemistry")
        #expect(picked.id == later.id)
        #expect(picked.id != SubjectFilter.other.id)
        #expect(SubjectFilter.subject(key: "", name: "").id != SubjectFilter.other.id)
    }

    @Test func daysWithoutTheSubjectDim() {
        let calendar = osloCalendar
        let first = calendar.startOfDay(for: start)
        let days = (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let sessions = [session("Chemistry", minutes: 25), session("Spanish", minutes: 25, at: 24),
                        session("chemistry", minutes: 25, at: 48)]
        let totals = SubjectTotals(sessions)
        let chemistry = SubjectFilter.subject(key: "chemistry", name: "Chemistry")
        let dimmed = chemistry.daysWithout(sessions, in: totals, days: days, calendar: calendar)
        #expect(dimmed == [calendar.startOfDay(for: start.addingTimeInterval(24 * 3_600))])
    }
}
