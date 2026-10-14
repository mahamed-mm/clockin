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
        let expected: [SubjectTotals.Subject] = [SubjectTotals.Subject(name: "Chemistry ", seconds: 4_500),
                                                 SubjectTotals.Subject(name: "Spanish", seconds: 1_500)]
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
}
