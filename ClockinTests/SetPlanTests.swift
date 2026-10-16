import Foundation
import Testing
@testable import Clockin

/// Today's plan: what it takes, how a finished session ticks it, and when it goes.
struct SetPlanTests {
    let day = osloCalendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    func plan(_ names: [String]) -> SetPlan {
        var plan = SetPlan(day: day)
        for name in names { plan.add(name) }
        return plan
    }

    @Test func itTakesUpToOneSet() {
        var plan = plan(["Chemistry", "Thesis", "Spanish", "Piano"])
        #expect(plan.slots.count == 4)
        let fifth = plan.add("Reading")
        #expect(!fifth)
        #expect(plan.slots.map(\.name) == ["Chemistry", "Thesis", "Spanish", "Piano"])
    }

    @Test func theSameNameCanBePlannedMoreThanOnce() {
        var plan = plan(["Thesis", " thesis ", "Chemistry", "Thesis"])
        #expect(plan.slots.map(\.name) == ["Thesis", "thesis", "Chemistry", "Thesis"])
        let fifth = plan.add("Thesis")
        #expect(!fifth, "Still one set at most")
        var other = self.plan(["Chemistry"])
        let blank = other.add("   ")
        #expect(!blank)
    }

    @Test func namesAreCleanedLikeASessionsName() {
        let plan = plan(["  Thesis,  chapter 2 "])
        #expect(plan.slots.first?.name == ActiveSession.cleanName("  Thesis,  chapter 2 "))
    }

    @Test func aFinishedSessionTicksTheFirstMatchingSlot() {
        var plan = plan(["Chemistry", "Thesis", "Spanish"])
        let session = UUID()
        let ticked = plan.finish(name: "CHEMISTRY ", session: session)
        #expect(ticked)
        #expect(plan.slots[0].doneBy == session)
        #expect(plan.next?.name == "Thesis")
    }

    @Test func slotsCanBeDoneOutOfOrder() {
        var plan = plan(["Chemistry", "Thesis"])
        plan.finish(name: "Thesis", session: UUID())
        #expect(plan.next?.name == "Chemistry")
    }

    @Test func anotherNameLeavesThePlanAlone() {
        var plan = plan(["Chemistry"])
        let other = plan.finish(name: "Emails", session: UUID())
        #expect(!other)
        let unnamed = plan.finish(name: "", session: UUID())
        #expect(!unnamed)
        #expect(plan.next?.name == "Chemistry")
    }

    @Test func accentsAreLettersOfTheirOwn() {
        var plan = plan(["Lås"])
        let withoutRing = plan.finish(name: "Las", session: UUID())
        #expect(!withoutRing)
        let withRing = plan.finish(name: "lås", session: UUID())
        #expect(withRing)
    }

    @Test func theSameSessionNeverTicksTwice() {
        var plan = plan(["Chemistry", "Chemistry 2"])
        plan.add("Thesis")
        let session = UUID()
        let first = plan.finish(name: "Chemistry", session: session)
        #expect(first)
        let second = plan.finish(name: "Thesis", session: session)
        #expect(!second)
        #expect(plan.slots.filter(\.isDone).count == 1)
    }

    @Test func aDeletedSessionsSlotIsToDoAgain() {
        var plan = plan(["Chemistry", "Thesis"])
        let gone = UUID(), kept = UUID()
        plan.finish(name: "Chemistry", session: gone)
        plan.finish(name: "Thesis", session: kept)
        plan.reopen(sessions: [gone])
        #expect(plan.slots.map(\.isDone) == [false, true])
    }

    @Test func slotsMoveAndGo() {
        var plan = plan(["A", "B", "C", "D"])
        plan.move(fromOffsets: [3], toOffset: 0)
        #expect(plan.slots.map(\.name) == ["D", "A", "B", "C"])
        plan.move(fromOffsets: [0], toOffset: 4)
        #expect(plan.slots.map(\.name) == ["A", "B", "C", "D"])
        plan.move(fromOffsets: [0], toOffset: 2)
        #expect(plan.slots.map(\.name) == ["B", "A", "C", "D"])
        plan.remove(id: plan.slots[1].id)
        #expect(plan.slots.map(\.name) == ["B", "C", "D"])
    }

    @Test func repeatedNamesAreTickedInOrder() {
        var plan = plan(["Thesis", "Thesis", "Chemistry", "Thesis"])
        for _ in 0..<3 { plan.finish(name: "THESIS", session: UUID()) }
        #expect(plan.slots.map(\.isDone) == [true, true, false, true])
        #expect(plan.next?.name == "Chemistry")
        let fourth = plan.finish(name: "Thesis", session: UUID())
        #expect(!fourth, "Every Thesis is done")
    }

    @Test func aRepeatMovedToTheFrontIsTickedFirst() {
        var plan = plan(["Thesis", "Chemistry", "Thesis"])
        let moved = plan.slots[2].id
        plan.move(fromOffsets: [2], toOffset: 0)
        plan.finish(name: "Thesis", session: UUID())
        #expect(plan.slots.first { $0.isDone }?.id == moved)
        #expect(plan.firstToDo(named: "Thesis")?.id == plan.slots[1].id)
    }

    @Test func removingOneOfTwoLeavesTheOther() {
        var plan = plan(["Thesis", "Chemistry", "Thesis"])
        let session = UUID()
        plan.finish(name: "Thesis", session: session)
        let kept = plan.slots[0]
        plan.remove(id: plan.slots[2].id)
        #expect(plan.slots.map(\.id) == [kept.id, plan.slots[1].id])
        #expect(plan.slots[0].doneBy == session)
        #expect(plan.next?.name == "Chemistry")
    }

    @Test func renamingRenamesEveryRepeatAndKeepsWhatsDone() {
        var plan = plan(["thesis", "Chemistry", "Thesis"])
        let session = UUID()
        plan.finish(name: "Thesis", session: session)
        plan.rename(key: "thesis", to: "Thesis outline")
        #expect(plan.slots.map(\.name) == ["Thesis outline", "Chemistry", "Thesis outline"])
        #expect(plan.slots.map(\.doneBy) == [session, nil, nil])
    }

    @Test func deletingOneRepeatsSessionReopensOnlyItsSlot() {
        var plan = plan(["Thesis", "Thesis", "Thesis"])
        let first = UUID(), second = UUID()
        plan.finish(name: "Thesis", session: first)
        plan.finish(name: "Thesis", session: second)
        plan.reopen(sessions: [first])
        #expect(plan.slots.map(\.isDone) == [false, true, false])
        let third = UUID()
        plan.finish(name: "Thesis", session: third)
        #expect(plan.slots[0].doneBy == third, "The earliest open one")
    }

    @Test func renamingASubjectRenamesItsSlots() {
        var plan = plan(["chem", "Thesis"])
        plan.rename(key: "chem", to: "Chemistry")
        #expect(plan.slots.map(\.name) == ["Chemistry", "Thesis"])
    }

    @Test func itBelongsToItsDay() {
        let plan = plan(["Chemistry"])
        #expect(plan.isFor(day: day.addingTimeInterval(23 * 3_600), calendar: osloCalendar))
        #expect(!plan.isFor(day: day.addingTimeInterval(25 * 3_600), calendar: osloCalendar))
    }

    @Test func itIsKeptAsJSONAndUnreadableDataIsNoPlan() throws {
        let defaults = try #require(UserDefaults(suiteName: "SetPlanTests"))
        defaults.removePersistentDomain(forName: "SetPlanTests")
        let store = DefaultsSetPlanStore(defaults: defaults)
        #expect(store.load() == nil)
        let saved = plan(["Chemistry", "Thesis"])
        store.save(saved)
        #expect(store.load() == saved)
        store.save(nil)
        #expect(store.load() == nil)
        defaults.set(Data("nope".utf8), forKey: store.key)
        #expect(store.load() == nil)
    }
}

/// The plan in the app: ticking, the field, the day moving on and Erase all.
@MainActor
struct SetPlanServicesTests {
    let clock = FakeClock()
    let widgets = SpyWidgets()
    let plans = InMemorySetPlanStore()
    let symbols = InMemorySymbolBookStore()

    final class Field {
        var name = ""
    }
    let field = Field()

    func makeServices() -> AppServices {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   symbolStore: symbols, planStore: plans, now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: SpyLiveActivity(), notifications: SpyNotifier(), widgets: widgets,
                                   haptics: SpyHaptics(), announce: { _ in })
        services.lastSessionName = { [field] in field.name }
        services.setLastSessionName = { [field] in field.name = $0 }
        return services
    }

    func planToday(_ services: AppServices, _ names: [String]) {
        var plan = SetPlan(day: services.today)
        for name in names { plan.add(name) }
        services.editSet(plan)
    }

    @Test func finishingAPlannedSessionTicksItAndFillsInTheNext() {
        let services = makeServices()
        planToday(services, ["Chemistry", "Thesis"])
        services.engine.start(name: "Chemistry")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(services.todaysSet?.slots.first?.isDone == true)
        #expect(services.nextPlanned?.name == "Thesis")
        #expect(field.name == "Thesis")
        #expect(services.planHandoff == services.todaysSet?.slots.last?.id)
        #expect(services.nextName(after: "Chemistry") == "Thesis")
        #expect(plans.plan == services.plannedSet)
    }

    @Test func finishNowCountsToo() {
        let services = makeServices()
        planToday(services, ["Chemistry"])
        services.engine.start(name: "Chemistry")
        clock.advance(10 * 60)
        services.engine.finishEarly()
        #expect(services.todaysSet?.slots.first?.isDone == true)
        #expect(services.nextPlanned == nil)
    }

    @Test func aCancelOrAnotherNameLeavesItAlone() {
        let services = makeServices()
        planToday(services, ["Chemistry"])
        services.engine.start(name: "Chemistry")
        services.engine.cancel()
        services.engine.start(name: "Emails")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(services.todaysSet?.slots.first?.isDone == false)
        #expect(services.nextName(after: "Emails") == "Chemistry")
    }

    @Test func withoutAPlanTheNextNameIsTheSameAgain() {
        let services = makeServices()
        #expect(services.nextName(after: "Emails") == "Emails")
        services.editSet(SetPlan(day: services.today))
        #expect(services.plannedSet == nil, "An empty plan is no plan")
    }

    @Test func itGoesQuietlyAtMidnight() {
        let services = makeServices()
        planToday(services, ["Chemistry"])
        clock.now = osloCalendar.date(byAdding: .day, value: 1, to: services.today)!.addingTimeInterval(60)
        services.timeChanged()
        #expect(services.plannedSet == nil)
        #expect(plans.plan == nil)
    }

    @Test func yesterdaysPlanIsNotShownOnAColdLaunch() {
        let yesterday = osloCalendar.date(byAdding: .day, value: -1, to: osloCalendar.startOfDay(for: clock.now))!
        var old = SetPlan(day: yesterday)
        old.add("Chemistry")
        plans.plan = old
        let services = makeServices()
        #expect(services.todaysSet == nil)
        services.restore()
        #expect(services.plannedSet == nil)
    }

    @Test func aRepeatHandsOverToItsNextSlot() {
        let services = makeServices()
        planToday(services, ["Thesis", "Thesis", "Chemistry"])
        services.engine.start(name: "Thesis")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        let slots = services.todaysSet?.slots ?? []
        #expect(slots.map(\.isDone) == [true, false, false])
        #expect(field.name == "Thesis")
        #expect(services.planHandoff == slots[1].id, "Moves in from the second Thesis")
        #expect(services.nextName(after: "Thesis") == "Thesis")
    }

    @Test func aSessionFinishingBeforeMidnightTicksThatDaysPlan() {
        // Started at 23:30 in Oslo, done at 23:55, found at 00:10.
        clock.now = osloCalendar.date(bySettingHour: 23, minute: 30, second: 0, of: clock.now)!
        let services = makeServices()
        planToday(services, ["Chemistry", "Thesis"])
        services.engine.start(name: "Chemistry")
        clock.advance(40 * 60)
        services.reconcile()
        // Ticked on its own day, so the next name came up, then the day moved on.
        #expect(field.name == "Thesis")
        #expect(services.plannedSet == nil)
    }

    @Test func aDeletedSessionReopensItsSlotOnceUndoHasGone() throws {
        let services = makeServices()
        planToday(services, ["Chemistry"])
        services.engine.start(name: "Chemistry")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        let id = try #require(services.engine.stage.completedFocus?.id)
        services.engine.skipBreak()
        services.deleteSessions([id])
        #expect(services.todaysSet?.slots.first?.isDone == true, "Still undoable")
        services.expireDeletion()
        #expect(services.todaysSet?.slots.first?.isDone == false)
    }

    @Test func eraseAllClearsIt() {
        let services = makeServices()
        planToday(services, ["Chemistry"])
        services.eraseHistory()
        #expect(services.plannedSet == nil)
    }

    @Test func aPlannedNamesSymbolIsKept() {
        let services = makeServices()
        planToday(services, ["Piano practice"])
        services.setSymbol("music.note", for: "Piano practice")
        services.pruneSymbols()
        #expect(services.symbol(for: "Piano practice") == "music.note")
    }

    @Test func aBackupHasNoPlan() throws {
        let services = makeServices()
        planToday(services, ["Chemistry"])
        let data = try HistoryExport.backup([], symbols: services.symbolBook, thoughts: services.thoughts,
                                            exportedAt: clock.now)
        #expect(String(data: data, encoding: .utf8)?.contains("Chemistry") == false)
    }
}

/// The plan sheet's recent names and the strip under the name field.
@MainActor
struct PlanStripTests {
    let day = osloCalendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func recentNamesStayWhileThereIsRoom() {
        var plan = SetPlan(day: day)
        plan.add("Chemistry")
        plan.add("Thesis")
        plan.finish(name: "Thesis", session: UUID())
        let recent = ["chemistry", "Thesis", "Spanish", "Piano", "Emails", "Journal", "Reading", "Algebra"]
        #expect(plan.suggestions(from: recent) == ["chemistry", "Thesis", "Spanish", "Piano", "Emails", "Journal"],
                "Planned names too: a subject can fill several slots")
        plan.add("Spanish")
        plan.add("Piano")
        #expect(plan.suggestions(from: recent).isEmpty, "A full plan offers nothing")
    }

    @Test func eachChipSaysWhereItStands() {
        var plan = SetPlan(day: day)
        plan.add("Chemistry")
        plan.add("Thesis outline")
        plan.add("Spanish")
        plan.finish(name: "Chemistry", session: UUID())
        let slots = plan.slots
        #expect(PlanStrip.state(of: slots[0], in: plan, typed: "Chemistry") == .done)
        #expect(PlanStrip.state(of: slots[1], in: plan, typed: " thesis OUTLINE") == .inField)
        #expect(PlanStrip.state(of: slots[2], in: plan, typed: "Thesis outline") == .toDo)
        #expect(PlanStrip.state(of: slots[2], in: plan, typed: "") == .toDo)
    }

    @Test func onlyTheFirstOpenRepeatIsInTheField() {
        var plan = SetPlan(day: day)
        for name in ["Thesis", "Chemistry", "Thesis", "Thesis"] { plan.add(name) }
        plan.finish(name: "Thesis", session: UUID())
        let states = plan.slots.map { PlanStrip.state(of: $0, in: plan, typed: "thesis") }
        #expect(states == [.done, .toDo, .inField, .toDo])
        // A later Thesis has nothing to put in the field; Chemistry does.
        #expect(plan.slots.map { PlanStrip.canPick($0, typed: "Thesis") } == [false, true, false, false])
        #expect(plan.slots.map { PlanStrip.canPick($0, typed: "") } == [false, true, true, true])
        #expect(PlanStrip.spoken(plan, typed: "Thesis")
                == "Today's plan: Thesis, done; Chemistry; Thesis, up next; Thesis")
    }

    @Test func theStripReadsAsOneLine() {
        var plan = SetPlan(day: day)
        plan.add("Chemistry")
        plan.add("Thesis outline")
        plan.add("Spanish")
        plan.finish(name: "Chemistry", session: UUID())
        #expect(PlanStrip.spoken(plan, typed: "Thesis outline")
                == "Today's plan: Chemistry, done; Thesis outline, up next; Spanish")
    }

    @Test func slotsAreReadWithTheirPlace() {
        #expect(Copy.planSlotSpoken("Chemistry", position: 1, of: 4, done: true) == "Chemistry, 1 of 4, done")
        #expect(Copy.planSlotSpoken("Thesis", position: 2, of: 4, done: false) == "Thesis, 2 of 4")
    }
}

/// The plan's next session wherever "next" is said: the break's card and
/// alert, quick actions and the large widget.
@MainActor
struct PlanNextTests {
    let clock = FakeClock()
    let live = SpyLiveActivity()
    let notifier = SpyNotifier()
    let widgets = SpyWidgets()

    func makeServices() -> AppServices {
        let services = AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                   planStore: InMemorySetPlanStore(), now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: live, notifications: notifier, widgets: widgets,
                                   haptics: SpyHaptics(), announce: { _ in })
        var field = ""
        services.lastSessionName = { field }
        services.setLastSessionName = { field = $0 }
        return services
    }

    func plan(_ services: AppServices, _ names: [String]) {
        var plan = SetPlan(day: services.today)
        for name in names { plan.add(name) }
        services.editSet(plan)
    }

    @Test func aBreakCarriesTheNextPlannedSession() {
        let services = makeServices()
        plan(services, ["Chemistry", "Thesis"])
        services.engine.start(name: "Chemistry")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        #expect(live.lastNext?.name == "Thesis")
        #expect(notifier.nextName == "Thesis")
        // A plan changed during the break: the card and the alert follow.
        plan(services, ["Chemistry", "Piano"])
        #expect(live.lastNext?.name == "Chemistry")
        #expect(notifier.nextName == "Chemistry")
    }

    @Test func aRepeatIsNextAfterItsFirst() {
        let services = makeServices()
        plan(services, ["Thesis", "Thesis"])
        services.engine.start(name: "Thesis")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        #expect(live.lastNext?.name == "Thesis")
        #expect(notifier.nextName == "Thesis")
        #expect(services.widgetSnapshot().next?.name == "Thesis")
    }

    @Test func focusNeverCarriesANextName() {
        let services = makeServices()
        plan(services, ["Chemistry"])
        services.engine.start(name: "Emails")
        #expect(live.lastNext == nil)
        #expect(notifier.nextName == nil)
    }

    @Test func withoutAPlanABreakStartsTheSameAgain() {
        let services = makeServices()
        services.engine.start(name: "Essay")
        clock.advance(Preset.classic.focus)
        services.reconcile()
        services.engine.startBreak()
        #expect(live.lastNext == nil)
        #expect(notifier.nextName == nil)
    }

    @Test func theBreaksCardAndAlertNameIt() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let rest = ActiveSession(id: UUID(), name: "Chemistry", phase: .rest, plannedDuration: 300,
                                 focusStartedAt: start, state: .running(endDate: start.addingTimeInterval(300)))
        let next = NextUp(name: "Thesis", symbol: "graduationcap.fill")
        let card = FocusActivityAttributes.ContentState(session: rest, completedToday: 1, breakDuration: 300, next: next)
        #expect(card.doneLine == "Next: Thesis · session 2 of 4")
        let plain = FocusActivityAttributes.ContentState(session: rest, completedToday: 1, breakDuration: 300)
        #expect(plain.doneLine == "Next: session 2 of 4")
        #expect(EndNotifier.content(for: rest, completedToday: 1, nextName: "Thesis").subtitle
                == "Next: Thesis · session 2 of 4")
        #expect(EndNotifier.content(for: rest, completedToday: 1).subtitle == "Next: Chemistry · session 2 of 4")
    }

    @Test func olderCardsAndSnapshotsLoadWithoutIt() throws {
        let rest = #"{"phase":"rest","plannedDuration":300,"endDate":0}"#
        let card = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: Data(rest.utf8))
        #expect(card.next == nil)
        let snapshot = #"{"sessions":[],"writtenAt":0}"#
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: Data(snapshot.utf8)).next == nil)
    }

    @Test func theWidgetShowsItOnlyOnItsDay() {
        let services = makeServices()
        plan(services, ["Chemistry"])
        let snapshot = services.widgetSnapshot()
        #expect(snapshot.next?.name == "Chemistry")
        #expect(snapshot.next(at: clock.now, calendar: osloCalendar)?.name == "Chemistry")
        #expect(snapshot.next(at: clock.now.addingTimeInterval(2 * 86_400), calendar: osloCalendar) == nil)
    }

    @Test func theNextPlannedSessionIsTheFirstQuickAction() {
        #expect(QuickAction.available(focusing: false, next: "Chemistry", recentNames: ["Essay", "Piano"])
                == [.start(name: "Chemistry"), .start(name: "Essay"), .history])
        #expect(QuickAction.available(focusing: false, next: "essay", recentNames: ["Essay", "Piano"])
                == [.start(name: "essay"), .start(name: "Piano"), .history])
        #expect(QuickAction.available(focusing: true, next: "Chemistry", recentNames: ["Essay"])
                == [.pause, .park, .history])
    }
}
