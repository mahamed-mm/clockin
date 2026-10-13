import Foundation
import Testing
@testable import Clockin

/// What VoiceOver reads: whole words, and a timer that doesn't chatter.
@MainActor
struct AccessibilityTextTests {
    @Test func durationsAreSpokenInWords() {
        #expect(TimeFormat.spokenDuration(25 * 60) == "25 minutes")
        #expect(TimeFormat.spokenDuration(60) == "1 minute")
        #expect(TimeFormat.spokenDuration(75 * 60) == "1 hour, 15 minutes")
        #expect(TimeFormat.spokenDuration(2 * 3_600) == "2 hours")
        #expect(TimeFormat.spokenDuration(10) == "10 seconds")
        #expect(TimeFormat.spokenDuration(0) == "0 minutes")
    }

    @Test func timeLeftRoundsUpLikeTheClock() {
        // 24:30 on the clock.
        #expect(TimeFormat.spokenTimeLeft(24 * 60 + 30) == "25 minutes left")
        #expect(TimeFormat.spokenTimeLeft(25 * 60) == "25 minutes left")
        #expect(TimeFormat.spokenTimeLeft(60.4) == "2 minutes left")
        #expect(TimeFormat.spokenTimeLeft(60) == "1 minute left")
    }

    @Test func theLastMinuteCountsInTenSecondSteps() {
        #expect(TimeFormat.spokenTimeLeft(59) == "1 minute left")
        #expect(TimeFormat.spokenTimeLeft(41) == "50 seconds left")
        #expect(TimeFormat.spokenTimeLeft(3) == "10 seconds left")
    }

    @Test func timeLeftChangesAboutOncePerMinute() {
        let spoken = Set(stride(from: 1_500.0, to: 1_200, by: -1).map(TimeFormat.spokenTimeLeft))
        #expect(spoken.count == 5)
    }

    @Test func pillsReadAsASet() {
        #expect(Copy.pillsSpoken(completed: 2, setSize: 4, inProgress: false) == "2 of 4 today")
        #expect(Copy.pillsSpoken(completed: 2, setSize: 4, inProgress: true) == "2 of 4 today, one in progress")
        #expect(Copy.pillsSpoken(completed: 6, setSize: 4, inProgress: false) == "6 focus sessions today")
        #expect(Copy.extendSpoken(seconds: 300) == "Add 5 minutes")
    }

    @Test func weekStripDaysSayWhichDayAndWhetherItsToday() {
        let calendar = osloCalendar
        func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d))! }
        let today = day(12)
        #expect(WeekStrip.accessibilityText(DayTotal(day: day(12), seconds: 3_000, sessions: 2), today: today,
                                            calendar: calendar, locale: Locale(identifier: "en_GB"))
                == "Monday 12 October, today: 2 sessions, 50 minutes")
        #expect(WeekStrip.accessibilityText(DayTotal(day: day(11), seconds: 1_500, sessions: 1), today: today,
                                            calendar: calendar, locale: Locale(identifier: "en_GB"))
                == "Sunday 11 October: 1 session, 25 minutes")
        #expect(WeekStrip.accessibilityText(DayTotal(day: day(13), seconds: 0, sessions: 0), today: today,
                                            calendar: calendar, locale: Locale(identifier: "en_GB"))
                == "Tuesday 13 October, upcoming")
    }
}

/// The dial takes what's left of the screen, and the page scrolls before
/// anything falls off it.
struct FocusLayoutTests {
    @Test func theDialFillsTheHeightLeft() {
        #expect(FocusLayout.dialSide(viewportHeight: 700, chrome: 400, minimum: 160, width: 340) == 300)
    }

    @Test func itIsNeverWiderThanTheColumn() {
        #expect(FocusLayout.dialSide(viewportHeight: 900, chrome: 300, minimum: 160, width: 340) == 340)
    }

    @Test func itStopsAtItsMinimumAndThePageScrolls() {
        #expect(FocusLayout.dialSide(viewportHeight: 600, chrome: 900, minimum: 200, width: 340) == 200)
        // A minimum wider than the column still fits the column.
        #expect(FocusLayout.dialSide(viewportHeight: 600, chrome: 900, minimum: 400, width: 320) == 320)
    }

    @Test func nothingIsDrawnBeforeTheFirstMeasurement() {
        #expect(FocusLayout.dialSide(viewportHeight: 0, chrome: 0, minimum: 160, width: 0) == 0)
    }
}
