import Foundation
import Testing
@testable import Clockin

/// Big totals in the widgets say exactly what the app says.
struct DurationTextTests {
    static let totals: [TimeInterval] = [0, 30, 59, 60, 45 * 60, 60 * 60, 75 * 60 + 40, 120 * 60, 645 * 60]

    @Test(arguments: totals)
    func theWidgetsDrawTheAppsText(_ seconds: TimeInterval) {
        let parts = TimeFormat.durationParts(seconds)
        let drawn = DurationText.attributed(parts, size: 40, bold: false)
        #expect(String(drawn.characters) == TimeFormat.duration(seconds))
        #expect(String(DurationText.attributed(parts, size: 40, bold: true).characters) == TimeFormat.duration(seconds))
    }

    @Test(arguments: totals)
    func numbersAreOnlyDigits(_ seconds: TimeInterval) {
        let parts = TimeFormat.durationParts(seconds)
        #expect(parts.filter(\.isNumber).allSatisfy { $0.text.allSatisfy(\.isNumber) })
        #expect(parts.filter { !$0.isNumber }.allSatisfy { !$0.text.contains { $0.isNumber } })
        #expect(parts.first?.isNumber == true)
    }

    @Test func itSplitsAnyLanguage() {
        #expect(TimeFormat.parts(of: "1 t 15 min").map(\.text) == ["1", " t ", "15", " min"])
        #expect(TimeFormat.parts(of: "1 t 15 min").map(\.isNumber) == [true, false, true, false])
        #expect(TimeFormat.parts(of: "45 min").map(\.text) == ["45", " min"])
    }

    @Test func itStacksHoursOverMinutes() {
        let lines = DurationText.lines(TimeFormat.parts(of: "10 h 45 min"))
        #expect(lines.map { $0.map(\.text).joined() } == ["10 h", "45 min"])
        #expect(DurationText.lines(TimeFormat.parts(of: "45 min")).count == 1)
    }

    @Test func itReadsTheTotalItShows() {
        // 74 min 40 s shows as "1 h 14 min", so it reads as 74 minutes too.
        let seconds: TimeInterval = 74 * 60 + 40
        #expect(TimeFormat.duration(seconds) == "1 h 14 min")
        #expect(TimeFormat.spokenDuration(TimeFormat.shownSeconds(seconds)) == TimeFormat.spokenDuration(74 * 60))
        #expect(TimeFormat.shownSeconds(30.6) == 30)
        #expect(Copy.spokenFocusedToday(seconds: 75 * 60).hasPrefix(TimeFormat.spokenDuration(75 * 60)))
    }
}
