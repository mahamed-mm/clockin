import Foundation
import SwiftUI
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

    private let full = CGSize(width: 402, height: 729)
    private let withKeyboard = CGSize(width: 402, height: 340)

    @Test func theParkFieldHoldsThePageAtItsSize() {
        let opened = FocusLayout.layoutViewport(measured: withKeyboard, current: full, held: false, fieldOpen: true)
        #expect(opened.size == full && opened.held)
        // The suggestions bar comes and goes: still held.
        let again = FocusLayout.layoutViewport(measured: CGSize(width: 402, height: 300), current: opened.size,
                                               held: opened.held, fieldOpen: true)
        #expect(again.size == full && again.held)
    }

    @Test func itStaysHeldWhileTheKeyboardLeaves() {
        let leaving = FocusLayout.layoutViewport(measured: CGSize(width: 402, height: 600), current: full,
                                                 held: true, fieldOpen: false)
        #expect(leaving.size == full && leaving.held)
        let back = FocusLayout.layoutViewport(measured: full, current: full, held: true, fieldOpen: false)
        #expect(back.size == full && !back.held)
    }

    @Test func aNewWidthLetsGo() {
        let rotated = CGSize(width: 874, height: 300)
        let laidOut = FocusLayout.layoutViewport(measured: rotated, current: full, held: true, fieldOpen: true)
        #expect(laidOut.size == rotated && !laidOut.held)
    }

    @Test func otherKeyboardsStillShrinkThePage() {
        // The name field's keyboard, with no park field: the page follows it as before.
        let laidOut = FocusLayout.layoutViewport(measured: withKeyboard, current: full, held: false, fieldOpen: false)
        #expect(laidOut.size == withKeyboard && !laidOut.held)
    }

    @Test func aHeldPageScrollsBackAsFarAsItWillFit() {
        // Fits once the keyboard has gone: all the way back.
        #expect(FocusLayout.scrollUnwind(scrolled: 80, contentHeight: 729, viewportHeight: 729) == 80)
        // Still 50 taller than the screen at large sizes: it stops there.
        #expect(FocusLayout.scrollUnwind(scrolled: 80, contentHeight: 779, viewportHeight: 729) == 30)
        #expect(FocusLayout.scrollUnwind(scrolled: 0, contentHeight: 729, viewportHeight: 729) == 0)
    }

    @Test func shortScreensGetTighterGaps() {
        #expect(FocusLayout.spacing(viewportHeight: 593) == Space.m)
        #expect(FocusLayout.spacing(viewportHeight: 729) == Space.l)
        // Before the first measurement, the usual gap.
        #expect(FocusLayout.spacing(viewportHeight: 0) == Space.l)
    }

    @Test func aTipAfterASessionNeedsRoom() {
        #expect(!FocusLayout.roomForTip(viewportHeight: 593))
        #expect(FocusLayout.roomForTip(viewportHeight: 729))
    }

    @Test func onlyAWideOrSidewaysSceneGoesSideBySide() {
        #expect(!FocusLayout.isWide(width: 375, height: 583))
        #expect(FocusLayout.isWide(width: 874, height: 360))
        #expect(FocusLayout.isWide(width: 700, height: 1000))
    }

    @Test func theParkFieldScrollsJustEnoughToKeepTickInSight() {
        // Tick's feet at 520 in the page, 418 visible above the field: down 102.
        #expect(FocusLayout.keepInSight(foot: 520, visibleHeight: 418, scrolled: 0) == 102)
        // Already in sight: stays put.
        #expect(FocusLayout.keepInSight(foot: 400, visibleHeight: 418, scrolled: 0) == 0)
        // Scrolled further than needed at a large size: back up until the foot is at the bottom.
        #expect(FocusLayout.keepInSight(foot: 520, visibleHeight: 418, scrolled: 300) == 102)
    }

    @Test func theHeaderStepsAsideOnlyWhileAFieldHasScrolledThePage() {
        #expect(FocusLayout.headerFaded(keyboardField: true, scrolled: 102))
        #expect(!FocusLayout.headerFaded(keyboardField: true, scrolled: 0), "Nothing under the status bar")
        #expect(!FocusLayout.headerFaded(keyboardField: false, scrolled: 102), "Scrolled by hand")
        #expect(!FocusLayout.headerFaded(keyboardField: false, scrolled: 0))
    }

    @Test func theSlipLandsWhereTickWillBe() {
        let window = CGRect(x: 0, y: 0, width: 402, height: 874)
        let tick = CGRect(x: 280, y: 380, width: 100, height: 100)
        #expect(FocusLayout.slipLanding(tick: tick, unwind: 60, window: window) == CGPoint(x: 330, y: 470))
        // Tick off the dial, or out of sight: no flight.
        #expect(FocusLayout.slipLanding(tick: .zero, unwind: 0, window: window) == nil)
        #expect(FocusLayout.slipLanding(tick: tick.offsetBy(dx: 0, dy: -500), unwind: 0, window: window) == nil)
    }
}

/// With Differentiate Without Color, the session in progress is dashed.
struct PillStrokeTests {
    @Test func theInProgressPillIsDashedOnlyWhenAsked() {
        let plain = SessionPills.currentStroke(pillHeight: 6, differentiateWithoutColor: false)
        #expect(plain.dash.isEmpty)
        #expect(plain.lineWidth == 1.5)

        let dashed = SessionPills.currentStroke(pillHeight: 6, differentiateWithoutColor: true)
        #expect(dashed.dash.count == 2)
        #expect(dashed.lineWidth == plain.lineWidth)
    }
}

/// The pill a completed session fills, and the liquid filling it.
struct LiquidPillTests {
    @Test func onlyAJustCompletedSessionFills() {
        #expect(SessionPills.fillingPill(from: 1, to: 2, justCompleted: true) == 1)
        // Launching, a restore or an undo isn't a completion.
        #expect(SessionPills.fillingPill(from: 1, to: 2, justCompleted: false) == nil)
        #expect(SessionPills.fillingPill(from: 0, to: 3, justCompleted: true) == nil)
        #expect(SessionPills.fillingPill(from: 2, to: 1, justCompleted: true) == nil)
        // Past the set there's no pill to fill, only the "+N".
        #expect(SessionPills.fillingPill(from: 4, to: 5, justCompleted: true) == nil)
        #expect(SessionPills.fillingPill(from: 3, to: 4, justCompleted: true) == 3)
    }

    @Test func emptyAndFullAreFlat() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 6)
        #expect(LiquidFill(level: 0).path(in: rect).isEmpty)
        #expect(LiquidFill(level: 1).path(in: rect) == Path(rect))
        #expect(LiquidFill.amplitude(at: 0) == 0)
        #expect(abs(LiquidFill.amplitude(at: 1)) < 1e-12)
        #expect(LiquidFill.amplitude(at: 0.5) > 0.1)
        // Fuller fills further.
        let half = LiquidFill(level: 0.5).path(in: rect).boundingRect
        let most = LiquidFill(level: 0.9).path(in: rect).boundingRect
        #expect(most.maxX > half.maxX)
        #expect(half.maxX > 5 && half.maxX < 15)
    }
}
