import Foundation
import Testing
@testable import Clockin

/// What the session card says about a saved session.
struct SessionSummaryTests {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_760_000_000)  // A Thursday afternoon.

    func summary(endingAgo ago: TimeInterval = 3600, focus: TimeInterval = 1500, planned: TimeInterval? = 1500,
                 outcome: FocusOutcome = .completed, name: String = "Thesis") -> SessionSummary {
        let end = now.addingTimeInterval(-ago)
        return SessionSummary(id: UUID(), name: name, startedAt: end.addingTimeInterval(-focus), completedAt: end,
                              focusSeconds: focus, plannedSeconds: planned, outcome: outcome)
    }

    func value(_ label: String, in summary: SessionSummary) -> String? {
        summary.rows.first { $0.label == label }?.value
    }

    @Test func onTimeSessionCounts() {
        let card = summary()
        #expect(card.rows.map(\.label) == ["Focused", "Planned", "Ended", "Set of four"])
        #expect(value("Focused", in: card) == "25 min")
        #expect(value("Ended", in: card) == "When time was up")
        #expect(value("Set of four", in: card) == "Counts")
    }

    @Test func earlySessionAtHalfItsPlanStillCounts() {
        let card = summary(focus: 750, planned: 1500, outcome: .endedEarly)
        #expect(value("Ended", in: card) == "Early, with Finish now")
        #expect(value("Set of four", in: card) == "Counts")
    }

    @Test func earlySessionUnderHalfDoesNotCount() {
        let card = summary(focus: 600, planned: 1500, outcome: .endedEarly)
        #expect(value("Set of four", in: card) == "Under half its plan")
        #expect(!card.countsAsFull)
    }

    @Test func sessionFrom1xHasNoPlannedRow() {
        let card = summary(planned: nil)
        #expect(value("Planned", in: card) == nil)
        #expect(value("Set of four", in: card) == "Counts")
    }

    @Test func unnamedSessionUsesTheDefaultTitle() {
        #expect(summary(name: "").title == Copy.displayName(""))
    }

    @Test func overlineNamesTheDay() {
        let today = summary(endingAgo: 60)
        #expect(today.overline(now: now, calendar: calendar).hasPrefix("Today · "))
        #expect(today.overline(now: now, calendar: calendar).contains("→"))

        let yesterday = summary(endingAgo: 86_400)
        #expect(yesterday.overline(now: now, calendar: calendar).hasPrefix("Yesterday · "))

        let older = summary(endingAgo: 5 * 86_400).overline(now: now, calendar: calendar)
        #expect(!older.hasPrefix("Today") && !older.hasPrefix("Yesterday"))
    }

    @Test func overlineBreaksBetweenTheDayAndTheTimes() {
        let card = summary(endingAgo: 86_400)
        let parts = card.overlineParts(now: now, calendar: calendar)
        #expect(parts.count == 2)
        #expect(parts[0] == "Yesterday")
        #expect(parts[1] == TimeFormat.range(card.startedAt, card.completedAt))
        #expect(!parts[1].contains("·"))
        #expect(parts.joined(separator: CardOverline.separator) == card.overline(now: now, calendar: calendar))
    }

    @Test func aRangeStacksOnlyAfterItsArrow() {
        #expect(CardOverline.stacked("13:15 → 13:40") == ["13:15 →", "13:40"])
        #expect(CardOverline.stacked("1:15 PM → 1:40 PM") == ["1:15 PM →", "1:40 PM"])
        #expect(CardOverline.stacked("Yesterday") == ["Yesterday"])
    }

    @Test func spokenOverlineHasNoArrow() {
        let spoken = summary(endingAgo: 60).spokenOverline(now: now, calendar: calendar)
        #expect(!spoken.contains("→"))
        #expect(spoken.contains(" to "))
    }
}
