import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import Clockin

/// The week's postcard: its facts, and the picture it makes.
@MainActor
struct WeekPostcardTests {
    let now = Date(timeIntervalSince1970: 1_791_986_400) // A Wednesday at 16:00 in Oslo.

    func facts(today: Date? = nil, weeksBack: Int = 1) -> PostcardFacts {
        let week = osloCalendar.weekInterval(containing: osloCalendar.date(byAdding: .weekOfYear, value: -weeksBack,
                                                                         to: now)!)
        let names = ["Chemistry", "Thesis outline", "Spanish vocab", "Piano", "Chemistry", "Chemistry", "Thesis outline"]
        let sessions = names.enumerated().map { index, name in
            SubjectTotals.Session(name: name, completedAt: week.start.addingTimeInterval(Double(index) * 86_400 / 2 + 36_000),
                                  seconds: 1_500)
        }
        let days = (0..<7).map { offset in
            let day = osloCalendar.date(byAdding: .day, value: offset, to: week.start)!
            let count = sessions.filter { osloCalendar.isDate($0.completedAt, inSameDayAs: day) }.count
            return DayTotal(day: day, seconds: Double(count) * 1_500, sessions: count)
        }
        return PostcardFacts(week: week, days: days, sessions: sessions, today: today ?? now) { _ in "flask.fill" }
    }

    @Test func itSaysTheWeekInFactsWithNamesOnlyWhenAsked() {
        let card = facts()
        #expect(card.sessions == 7)
        #expect(card.totalSeconds == 7 * 1_500)
        #expect(card.subjects.map(\.name) == ["Chemistry", "Thesis outline", "Piano"])
        let plain = card.description(showsNames: false, calendar: osloCalendar, locale: Locale(identifier: "en_GB"))
        #expect(plain.hasPrefix("A week of focus, "))
        #expect(plain.hasSuffix(": 2 hours, 55 minutes over 7 sessions."))
        #expect(!plain.contains("Chemistry"))
        let named = card.description(showsNames: true, calendar: osloCalendar, locale: Locale(identifier: "en_GB"))
        #expect(named.hasSuffix("Most of it on Chemistry, Thesis outline and Piano."))
    }

    @Test func tickPutsItsFeetUpOnlyOnceTheWeekIsOver() {
        #expect(facts().pose == .onBreak)
        #expect(facts(weeksBack: 0).pose == .ready)
    }

    @Test func theDatesAreInThePhonesLanguage() {
        let english = facts().dates(calendar: osloCalendar, locale: Locale(identifier: "en_GB"))
        let norwegian = facts().dates(calendar: osloCalendar, locale: Locale(identifier: "nb_NO"))
        #expect(english != norwegian)
        #expect(norwegian.lowercased().contains("okt") || norwegian.lowercased().contains("sep"))
    }

    @Test func itDraws1080By1350WithItsGrainAndSaysWhatItShows() throws {
        let image = try #require(PostcardRenderer.image(facts(), showsNames: true, today: now, calendar: osloCalendar))
        #expect(image.width == 1_080 && image.height == 1_350)
        // A patch of plain paper in the corner: the grain makes it more than one shade.
        let corner = try #require(image.cropping(to: CGRect(x: 6, y: 1_300, width: 40, height: 40)))
        #expect(PaperGrainRenderTests.distinctLevels(corner) > 3)

        let description = "A week of focus."
        let png = try #require(PostcardRenderer.png(image, description: description))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let pngInfo = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        #expect(pngInfo?[kCGImagePropertyPNGDescription] as? String == description)

    }
}
