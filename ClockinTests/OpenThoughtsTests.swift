import Foundation
import SwiftUI
import Testing
@testable import Clockin

/// History's open thoughts: by subject, the cancelled ones last, done ones gone.
struct OpenThoughtsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func thought(_ text: String, hoursAgo: Double, done: Bool = false) -> ParkedThought {
        ParkedThought(id: UUID(), text: text, parkedAt: now.addingTimeInterval(-hoursAgo * 3_600), done: done ? true : nil)
    }

    @Test func thoughtsGatherBySubjectNewestFirstWithTheCancelledLast() {
        let chemistry = UUID(), chem = UUID(), essay = UUID()
        var book = ThoughtBook()
        book.file([thought("Old lab", hoursAgo: 30)], under: chemistry)
        book.file([thought("Titration", hoursAgo: 2), thought("Done one", hoursAgo: 1, done: true)], under: chem)
        book.file([thought("Outline", hoursAgo: 5)], under: essay)
        book.unfile([thought("Dentist", hoursAgo: 1)])
        let open = OpenThoughts(book: book, names: [chemistry: "Chemistry", chem: "chemistry ", essay: "Essay"])
        #expect(open.groups.map(\.key) == ["chemistry", "essay", nil])
        #expect(open.groups[0].name == "chemistry ", "As the newest session spells it")
        #expect(open.groups[0].thoughts.map(\.text) == ["Titration", "Old lab"])
        #expect(open.groups.last?.thoughts.map(\.text) == ["Dentist"])
        #expect(open.openCount == 4)
        #expect(open.plainText == "Titration\nOld lab\nOutline\nDentist")
    }

    @Test func aSessionWithoutANameIsLeftOut() {
        var book = ThoughtBook()
        book.file([thought("Gone", hoursAgo: 1)], under: UUID())
        #expect(OpenThoughts(book: book, names: [:]).isEmpty)
    }

    @Test func oneTickedOffMomentsAgoStaysWhileItFolds() {
        let essay = UUID()
        let done = thought("Outline", hoursAgo: 1, done: true)
        var book = ThoughtBook()
        book.file([done], under: essay)
        #expect(OpenThoughts(book: book, names: [essay: "Essay"]).isEmpty)
        let folding = OpenThoughts(book: book, names: [essay: "Essay"], keeping: [done.id])
        #expect(folding.groups.first?.thoughts == [done])
        #expect(folding.openCount == 0)
    }

    @Test func datesReadAsDaysThenDates() {
        let today = osloCalendar.startOfDay(for: now)
        func text(_ daysAgo: Int) -> String {
            OpenThoughts.dateText(osloCalendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(3_600),
                                  today: today, calendar: osloCalendar)
        }
        #expect(text(0) == "Today")
        #expect(text(1) == "Yesterday")
        let weekday = text(3), date = text(10)
        #expect(!weekday.contains { $0.isNumber }, "A weekday")
        #expect(date.contains { $0.isNumber }, "A date")
    }

    @Test func clearTickedForgetsOnlyTheDoneOnes() {
        var book = ThoughtBook()
        let session = UUID()
        book.file([thought("Open", hoursAgo: 1), thought("Done", hoursAgo: 2, done: true)], under: session)
        book.file([thought("All done", hoursAgo: 2, done: true)], under: UUID())
        book.unfile([thought("Done too", hoursAgo: 3, done: true), thought("Still", hoursAgo: 3)])
        #expect(book.hasDone)
        book.clearDone()
        #expect(!book.hasDone)
        #expect(book.bySession.count == 1)
        #expect(book.thoughts(for: session).map(\.text) == ["Open"])
        #expect(book.unfiled.map(\.text) == ["Still"])
    }

    @Test func thePenRunsLineByLine() {
        let lines = [CGRect(x: 0, y: 0, width: 100, height: 20), CGRect(x: 0, y: 20, width: 50, height: 20)]
        #expect(PenStroke.strokes(lines: lines, progress: 0).isEmpty)
        let half = PenStroke.strokes(lines: lines, progress: 0.5)
        #expect(half.count == 1)
        #expect(half[0].1.x == 75)
        let full = PenStroke.strokes(lines: lines, progress: 1)
        #expect(full.count == 2)
        #expect(full[0].1.x == 100 && full[1].1.x == 50)
        #expect(full[1].0.y == 31, "Through the middle of the letters")
    }
}

/// Ticking off and clearing in the app, with Undo.
@MainActor
struct OpenThoughtsServicesTests {
    let clock = FakeClock()

    func makeServices() -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                    now: { [clock] in clock.now }, calendar: osloCalendar, schedulesCompletion: false,
                    liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), widgets: SpyWidgets(),
                    haptics: SpyHaptics(), announce: { _ in })
    }

    func finishWithThoughts(_ services: AppServices, _ texts: [String]) {
        services.engine.start(name: "Essay")
        for text in texts { services.park(text) }
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.skipBreak()
    }

    @Test func tickingOffCanBeUndone() throws {
        let services = makeServices()
        finishWithThoughts(services, ["Email Sam", "Book the dentist"])
        #expect(services.openThoughts().openCount == 2)
        let first = try #require(services.openThoughts().groups.first?.thoughts.first)
        services.tickOffThought(first.id)
        #expect(services.openThoughts().openCount == 1)
        guard case .thoughts(_, false)? = services.historyUndo else { Issue.record("No undo"); return }
        services.undoHistoryChange()
        #expect(services.openThoughts().openCount == 2)
    }

    @Test func clearTickedCanBeUndoneToo() throws {
        let services = makeServices()
        finishWithThoughts(services, ["Email Sam"])
        let thought = try #require(services.openThoughts().groups.first?.thoughts.first)
        services.tickOffThought(thought.id)
        services.clearTickedThoughts()
        #expect(!services.thoughts.hasDone)
        services.undoHistoryChange()
        #expect(services.thoughts.hasDone)
    }

    @Test func aDeletedSessionsThoughtsLeaveTheList() throws {
        let services = makeServices()
        finishWithThoughts(services, ["Email Sam"])
        let id = try #require(services.thoughts.bySession.keys.first)
        services.deleteSessions([id])
        #expect(services.openThoughts().isEmpty, "Hidden while the delete can be undone")
        services.expireDeletion()
        #expect(services.thoughts.bySession.isEmpty, "Pruned once it can't")
    }

    @Test func aCancelledSessionsThoughtsAreHereUnderTheirOwnHeading() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        services.park("Water the plants")
        services.engine.cancel()
        #expect(services.openThoughts().groups.map(\.key) == [nil])
    }
}
