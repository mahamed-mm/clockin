import Foundation
import SwiftData
import Testing
@testable import Clockin

/// Data written by 1.0 must keep loading after every change to the models.
@MainActor
struct HistoryStoreCompatibilityTests {
    /// `Fixtures/ClockinV1.store` is a real store written by 1.0, before the
    /// schema was versioned: 19 sessions, captured from the simulator.
    @Test func opensAStoreWrittenBeforeVersioning() throws {
        let container = try SharedStore.makeModelContainer(url: try copyOfFixture())
        let records = try ModelContext(container).fetch(FetchDescriptor<FocusRecord>())

        #expect(records.count == 19)
        #expect(Set(records.map(\.name)).isSuperset(of: ["Chemistry", "Spanish vocab", "Thesis outline"]))
        #expect(records.allSatisfy { $0.focusSeconds > 0 && $0.completedAt > $0.startedAt })
    }

    @Test func upgradedStoreKeepsWorking() throws {
        let url = try copyOfFixture()
        do {
            let log = SwiftDataFocusLog(container: try SharedStore.makeModelContainer(url: url))
            try log.record(CompletedFocus(id: UUID(), name: "After upgrade", startedAt: .now,
                                          completedAt: .now.addingTimeInterval(1_500), focusSeconds: 1_500))
        }
        let reopened = try SharedStore.makeModelContainer(url: url)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<FocusRecord>()) == 20)
    }

    @Test func upgradeLeavesOldSessionsWithoutTheNewFields() throws {
        let container = try SharedStore.makeModelContainer(url: try copyOfFixture())
        let records = try ModelContext(container).fetch(FetchDescriptor<FocusRecord>())

        #expect(records.count == 19)
        #expect(records.allSatisfy { $0.plannedSeconds == nil && $0.timeZoneIdentifier == nil && $0.outcomeRaw == nil })
        #expect(records.allSatisfy { $0.outcome == .completed && $0.row.countsAsFull })
    }

    @Test func newFieldsSurviveAReopen() throws {
        let url = try copyOfFixture()
        let id = UUID()
        do {
            let log = SwiftDataFocusLog(container: try SharedStore.makeModelContainer(url: url))
            try log.record(CompletedFocus(id: id, name: "Early", startedAt: .now, completedAt: .now.addingTimeInterval(600),
                                          focusSeconds: 600, plannedSeconds: 1_500, outcome: .endedEarly))
        }
        let reopened = try SharedStore.makeModelContainer(url: url)
        let saved = try #require(try ModelContext(reopened).fetch(FetchDescriptor<FocusRecord>(
            predicate: #Predicate { $0.id == id })).first)
        #expect(saved.plannedSeconds == 1_500)
        #expect(saved.outcome == .endedEarly)
        #expect(saved.timeZoneIdentifier == TimeZone.current.identifier)
        #expect(!saved.row.countsAsFull)
    }

    /// The widget opens the store read-only. Against a store the app hasn't
    /// upgraded yet, that must leave the file alone, so the app can still.
    @Test func aReadOnlyOpenNeverTouchesAnOldStore() throws {
        let url = try copyOfFixture()
        let before = try Data(contentsOf: url)
        _ = try? SharedStore.makeModelContainer(url: url, readOnly: true)
        #expect(try Data(contentsOf: url) == before)

        let upgraded = try SharedStore.makeModelContainer(url: url)
        #expect(try ModelContext(upgraded).fetchCount(FetchDescriptor<FocusRecord>()) == 19)
    }

    private func copyOfFixture() throws -> URL {
        let fixture = try #require(Bundle(for: FakeClock.self).url(forResource: "ClockinV1", withExtension: "store"))
        let folder = FileManager.default.temporaryDirectory.appending(path: "clockin-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Clockin.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }
}

struct SessionStateCompatibilityTests {
    // Exactly what 1.0 wrote, produced by encoding with the code at cb0a08e.
    static let running = #"{"active":{"focusStartedAt":800000000,"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Thesis outline","phase":"focus","plannedDuration":1500,"state":{"running":{"endDate":800001500}}}}"#
    static let pausedBreak = #"{"active":{"focusStartedAt":800000000,"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Thesis outline","phase":"rest","plannedDuration":300,"state":{"paused":{"remaining":120}}}}"#
    static let complete = #"{"completedFocusName":"Thesis outline"}"#
    static let idle = "{}"

    @Test func readsARunningSessionFrom1_0() throws {
        let state = try decode(Self.running)
        let session = try #require(state.active)
        #expect(session.id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF"))
        #expect(session.name == "Thesis outline")
        #expect(session.phase == .focus)
        #expect(session.plannedDuration == 1_500)
        #expect(session.state == .running(endDate: Date(timeIntervalSinceReferenceDate: 800_001_500)))
        #expect(state.format == nil)
        #expect(state.pendingRecords == nil)
    }

    @Test func readsAPausedBreakFrom1_0() throws {
        let session = try #require(try decode(Self.pausedBreak).active)
        #expect(session.phase == .rest)
        #expect(session.state == .paused(remaining: 120))
        // 1.0 didn't save when it paused; the header then just says "Paused".
        #expect(session.pausedAt == nil)
    }

    @Test func readsCompletionAndIdleFrom1_0() throws {
        #expect(try decode(Self.complete).completedFocusName == "Thesis outline")
        let idle = try decode(Self.idle)
        #expect(idle.active == nil && idle.completedFocusName == nil)
    }

    @Test func runStateStillWritesThe1_0Shape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let running = ActiveSession.RunState.running(endDate: Date(timeIntervalSinceReferenceDate: 800_001_500))
        #expect(String(decoding: try encoder.encode(running), as: UTF8.self) == #"{"running":{"endDate":800001500}}"#)
        let paused = ActiveSession.RunState.paused(remaining: 120)
        #expect(String(decoding: try encoder.encode(paused), as: UTF8.self) == #"{"paused":{"remaining":120}}"#)
    }

    @Test func ignoresFieldsFromNewerBuilds() throws {
        let future = #"{"completedFocusName":"Essay","format":9,"somethingNew":{"x":1}}"#
        #expect(try decode(future).completedFocusName == "Essay")
    }

    @Test func pendingSessionsRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let store = DefaultsSessionStateStore(defaults: defaults)
        let pending = CompletedFocus(id: UUID(), name: "Essay", startedAt: Date(timeIntervalSinceReferenceDate: 0),
                                     completedAt: Date(timeIntervalSinceReferenceDate: 1_500), focusSeconds: 1_500)
        let state = PersistedSessionState(completedFocusName: "Essay", pendingRecords: [pending])
        store.save(state)
        #expect(store.load() == state)
        #expect(store.load().format == PersistedSessionState.currentFormat)
    }

    @Test func unreadableStateStartsIdleAndKeepsACopy() throws {
        let defaults = try #require(UserDefaults(suiteName: "clockin.tests.\(UUID())"))
        let store = DefaultsSessionStateStore(defaults: defaults)
        let garbled = Data(#"{"active":{"state":{"sideways":{}}}}"#.utf8)
        defaults.set(garbled, forKey: store.key)

        #expect(store.load() == PersistedSessionState())
        #expect(defaults.data(forKey: store.unreadableKey) == garbled)
    }

    private func decode(_ json: String) throws -> PersistedSessionState {
        try JSONDecoder().decode(PersistedSessionState.self, from: Data(json.utf8))
    }
}
