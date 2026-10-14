import Foundation
import Testing
@testable import Clockin

/// The demo history behind screenshots: believable, and the same every time.
struct DemoHistoryTests {
    /// A Wednesday at 16:00 in Oslo.
    let now = Date(timeIntervalSince1970: 1_791_986_400)

    var sessions: [DemoHistory.Session] { DemoHistory.make(now: now, calendar: osloCalendar) }

    @Test func theSameDayGivesTheSameHistory() {
        #expect(sessions == DemoHistory.make(now: now, calendar: osloCalendar))
        #expect(sessions.count > 60)
    }

    @Test func itSpansSixWeeks() throws {
        let first = try #require(sessions.map(\.startedAt).min())
        let weeks = osloCalendar.dateComponents([.day], from: first, to: now).day ?? 0
        #expect((35...42).contains(weeks))
    }

    @Test func sessionsNeverOverlapAndStayInTheirDay() {
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        for (before, after) in zip(sorted, sorted.dropFirst()) {
            #expect(before.completedAt <= after.startedAt)
        }
        for session in sessions {
            #expect(osloCalendar.isDate(session.startedAt, inSameDayAs: session.completedAt))
            #expect(session.completedAt <= now)
        }
    }

    @Test func itHasTheDaysScreenshotsNeed() {
        let byDay = Dictionary(grouping: sessions) { osloCalendar.startOfDay(for: $0.completedAt) }
        #expect(byDay.values.contains { $0.count >= 6 })
        #expect(sessions.contains { osloCalendar.component(.hour, from: $0.startedAt) < 6 })
        #expect(sessions.contains { osloCalendar.component(.hour, from: $0.startedAt) >= 22 })
        let early = sessions.filter { $0.outcome == .endedEarly }
        #expect(early.count == 2)
        #expect(early.contains { $0.focusSeconds >= $0.plannedSeconds / 2 })
        #expect(early.contains { $0.focusSeconds < $0.plannedSeconds / 2 })
        #expect(Set(sessions.map(\.name)) == Set(DemoHistory.names))
        #expect(sessions.filter { osloCalendar.isDate($0.completedAt, inSameDayAs: now) }.count == 3)
    }

    @Test func picksAreOfferedSymbols() {
        for symbol in DemoHistory.picks.values { #expect(SymbolCatalog.contains(symbol)) }
    }
}
