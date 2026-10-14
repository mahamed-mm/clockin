import Foundation
import SwiftUI
import Testing
@testable import Clockin

/// The selected day's ribbon, and which day a week opens on.
struct DayRibbonTests {
    let day = osloCalendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!

    func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }

    func session(_ start: Double, _ end: Double, full: Bool = true, name: String = "Chemistry")
        -> DayRibbonLayout.Session {
        DayRibbonLayout.Session(id: UUID(), name: name, startedAt: at(start), completedAt: at(end),
                                seconds: (end - start) * 3_600, countsAsFull: full)
    }

    func layout(_ sessions: [DayRibbonLayout.Session], width: CGFloat = 180) -> DayRibbonLayout {
        DayRibbonLayout(sessions: sessions, day: day, calendar: osloCalendar, width: width)
    }

    @Test func aDayRunsFromSixToMidnight() {
        #expect(layout([]).hours == 6...24)
        #expect(layout([session(9, 9.5)]).hours == 6...24)
    }

    @Test func anEarlySessionWidensTheDayToItsHour() {
        #expect(layout([session(5 + 40.0 / 60, 6 + 5.0 / 60)]).hours == 5...24)
        // Started before midnight: the ribbon starts at midnight.
        #expect(layout([session(-0.5, 0.25)]).hours == 0...24)
    }

    @Test func blocksSitWhereTheirTimesAre() throws {
        // 18 hours over 180 points: 10 points an hour.
        let block = try #require(layout([session(9, 9.5)]).blocks.first)
        #expect(block.x == 30)
        #expect(block.width == DayRibbonLayout.minimumWidth) // Half an hour is 5 points, under the minimum.
        let long = try #require(layout([session(12, 14)]).blocks.first)
        #expect(long.x == 60)
        #expect(long.width == 20)
        // A block at the very end stays inside.
        let late = try #require(layout([session(23.95, 24)]).blocks.first)
        #expect(late.x + late.width <= 180)
    }

    @Test func coloursFollowTheSetAndSkipShortSessions() {
        let blocks = layout([session(8, 8.4), session(9, 9.1, full: false), session(10, 10.4), session(11, 11.4),
                             session(12, 12.4), session(13, 13.4)]).blocks
        #expect(blocks.map(\.position) == [0, nil, 1, 2, 3, 0])
    }

    @Test func aTapOpensTheBlockUnderItOrTheNearest() throws {
        let first = session(9, 9.5), second = session(10, 10.5)
        let ribbon = layout([first, second])
        #expect(ribbon.block(nearest: 32)?.id == first.id) // On it.
        #expect(ribbon.block(nearest: 50)?.id == second.id) // Nearer the second.
        #expect(ribbon.block(nearest: 120) == nil) // Out of reach.
        // Halfway between two, the later one.
        let between = layout([session(9, 9.5), session(10.1, 10.5)])
        #expect(between.block(nearest: 38.5)?.id == between.blocks[1].id)
    }

    @Test func positionsWrapToRust() {
        #expect(Retro.setColor(position: 0) == Retro.rust)
        #expect(Retro.setColor(position: 1) == Retro.orange)
        #expect(Retro.setColor(position: 3) == Retro.avocado)
        #expect(Retro.setColor(position: 4) == Retro.rust)
    }

    @Test func aBlockReadsItsNameAndTimes() {
        let text = Copy.ribbonBlock(name: "Chemistry", from: at(19), to: at(19 + 25.0 / 60))
        #expect(text.hasPrefix("Chemistry, "))
        #expect(text.contains(" to "))
    }

    // MARK: The day a week opens on

    func week(sessions: [Int]) -> [DayTotal] {
        sessions.enumerated().map { index, count in
            DayTotal(day: osloCalendar.date(byAdding: .day, value: index, to: day)!,
                     seconds: Double(count) * 1_500, sessions: count)
        }
    }

    @Test func thisWeekOpensOnToday() {
        let totals = week(sessions: [3, 0, 2, 0, 0, 0, 0])
        #expect(WeekStrip.defaultDay(totals, today: totals[2].day.addingTimeInterval(3_600), calendar: osloCalendar)
                == totals[2].day)
    }

    @Test func anEarlierWeekOpensOnItsLastDayWithSessions() {
        let today = osloCalendar.date(byAdding: .day, value: 30, to: day)!
        let busy = week(sessions: [3, 0, 2, 0, 0, 0, 0])
        #expect(WeekStrip.defaultDay(busy, today: today, calendar: osloCalendar) == busy[2].day)
        let empty = week(sessions: [0, 0, 0, 0, 0, 0, 0])
        #expect(WeekStrip.defaultDay(empty, today: today, calendar: osloCalendar) == empty[0].day)
    }
}
