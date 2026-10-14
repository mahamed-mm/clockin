import Foundation
import Testing
@testable import Clockin

/// The month view's grid, totals and set-coloured rings.
struct MonthGridTests {
    func calendar(firstWeekday: Int) -> Calendar {
        var calendar = osloCalendar
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    func month(_ year: Int, _ month: Int, _ calendar: Calendar) -> DateInterval {
        calendar.monthInterval(containing: calendar.date(from: DateComponents(year: year, month: month, day: 10))!)
    }

    @Test(arguments: [1, 2])
    func everyDayOnceInWeeksOfSeven(firstWeekday: Int) {
        let calendar = calendar(firstWeekday: firstWeekday)
        for monthNumber in 1...12 {
            let interval = month(2026, monthNumber, calendar)
            let rows = MonthGrid.rows(month: interval, calendar: calendar)
            #expect((4...6).contains(rows.count))
            #expect(rows.allSatisfy { $0.count == 7 })
            let days = rows.flatMap { $0 }.compactMap { $0 }
            let length = calendar.range(of: .day, in: .month, for: interval.start)!.count
            #expect(days.count == length)
            #expect(days.first == interval.start)
            // Each day sits in its weekday's column.
            for row in rows {
                for (column, day) in row.enumerated() {
                    guard let day else { continue }
                    #expect((calendar.component(.weekday, from: day) - firstWeekday + 7) % 7 == column)
                }
            }
        }
    }

    @Test func aMonthStartingOnTheFirstWeekdayHasNoLeadingBlanks() {
        let calendar = calendar(firstWeekday: 2)
        // June 2026 starts on a Monday; February 2026 on a Sunday.
        #expect(MonthGrid.rows(month: month(2026, 6, calendar), calendar: calendar)[0][0] != nil)
        let february = MonthGrid.rows(month: month(2026, 2, calendar), calendar: calendar)
        #expect(february[0].prefix(6).allSatisfy { $0 == nil })
        #expect(february[0][6] != nil)
    }

    @Test func daylightSavingMonthsKeepEveryDay() {
        let calendar = calendar(firstWeekday: 2)
        for monthNumber in [3, 10] {
            let days = MonthGrid.rows(month: month(2026, monthNumber, calendar), calendar: calendar)
                .flatMap { $0 }.compactMap { $0 }
            #expect(days.count == 31)
            #expect(Set(days.map { calendar.component(.day, from: $0) }).count == 31)
        }
    }

    @Test func weekdayInitialsFollowTheFirstWeekday() {
        #expect(MonthGrid.weekdaySymbols(calendar: calendar(firstWeekday: 2)).count == 7)
        let sunday = MonthGrid.weekdaySymbols(calendar: calendar(firstWeekday: 1))
        let monday = MonthGrid.weekdaySymbols(calendar: calendar(firstWeekday: 2))
        #expect(Array(sunday.dropFirst()) + [sunday[0]] == monday)
    }

    @Test func monthTotalsCountEachDayOnce() {
        let interval = month(2026, 10, osloCalendar)
        let day = osloCalendar.date(byAdding: .day, value: 13, to: interval.start)!
        let saved = [FocusRow(completedAt: day.addingTimeInterval(9 * 3_600), seconds: 1_500),
                     FocusRow(completedAt: day.addingTimeInterval(10 * 3_600), seconds: 600, countsAsFull: false)]
        let waiting = CompletedFocus(id: UUID(), name: "", startedAt: day.addingTimeInterval(11 * 3_600),
                                     completedAt: day.addingTimeInterval(11.5 * 3_600), focusSeconds: 1_500)
        let outside = CompletedFocus(id: UUID(), name: "", startedAt: interval.end, completedAt: interval.end,
                                     focusSeconds: 1_500)
        let totals = TodayStats.dayTotals(saved: saved, pending: [waiting, outside], in: interval,
                                          calendar: osloCalendar)
        #expect(totals.count == 31)
        #expect(totals[13] == DayTotal(day: day, seconds: 3_600, sessions: 2))
        #expect(totals.reduce(0) { $0 + $1.sessions } == 2)
    }

    @Test func aDaysRingIsQuartersInSetOrder() {
        #expect(RetroDial.setSegments(value: 0).isEmpty)
        #expect(RetroDial.setSegments(value: 0.5).map(\.position) == [0, 1])
        #expect(RetroDial.setSegments(value: 1).map(\.position) == [0, 1, 2, 3])
        let segments = RetroDial.setSegments(value: 1)
        for (before, after) in zip(segments, segments.dropFirst()) { #expect(before.to < after.from) }
    }
}
