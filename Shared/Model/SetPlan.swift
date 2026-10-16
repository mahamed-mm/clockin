import Foundation

/// An optional plan for today: up to four names, in the order they're
/// meant to come. A slot is done when a focus session with its name
/// finishes (at the bell or with Finish now); starting something else
/// leaves the plan as it is. It belongs to one day and is dropped quietly
/// when the day moves on. Pure, so it can be tested.
struct SetPlan: Codable, Equatable, Sendable {
    struct Slot: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        /// As typed, cleaned like a session's name.
        var name: String
        /// The session that finished it.
        var doneBy: UUID?

        var isDone: Bool { doneBy != nil }
    }

    /// The most a plan holds: one set.
    static let capacity = TimerPlan.sessionsPerSet

    /// Start of the day it belongs to.
    var day: Date
    var slots: [Slot] = []

    init(day: Date, slots: [Slot] = []) {
        self.day = day
        self.slots = slots
    }

    /// The first slot still to do.
    var next: Slot? { slots.first { !$0.isDone } }

    var isEmpty: Bool { slots.isEmpty }

    func isFor(day other: Date, calendar: Calendar) -> Bool {
        calendar.isDate(day, inSameDayAs: other)
    }

    /// Whether `name` can be added: there's room, it isn't blank, and it
    /// isn't already planned and still to do.
    func canAdd(_ name: String) -> Bool {
        let key = SymbolBook.key(for: name)
        guard !key.isEmpty, slots.count < Self.capacity else { return false }
        return !slots.contains { !$0.isDone && SymbolBook.key(for: $0.name) == key }
    }

    /// Adds a name at the end. False when it can't be added.
    @discardableResult
    mutating func add(_ name: String, id: UUID = UUID()) -> Bool {
        guard canAdd(name) else { return false }
        slots.append(Slot(id: id, name: ActiveSession.cleanName(name)))
        return true
    }

    mutating func remove(id: UUID) {
        slots.removeAll { $0.id == id }
    }

    /// A drag in the list: the slots at `source` go before the one at `destination`.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.compactMap { slots.indices.contains($0) ? slots[$0] : nil }
        var rest = slots.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let at = destination - source.count(in: 0..<max(0, destination))
        rest.insert(contentsOf: moving, at: min(max(0, at), rest.count))
        slots = rest
    }

    /// A focus session with this name finished: the first slot still to do
    /// with the same name is done. The same session never ticks two.
    /// Returns whether a slot was ticked.
    @discardableResult
    mutating func finish(name: String, session: UUID) -> Bool {
        guard !slots.contains(where: { $0.doneBy == session }) else { return false }
        let key = SymbolBook.key(for: name)
        guard !key.isEmpty,
              let index = slots.firstIndex(where: { !$0.isDone && SymbolBook.key(for: $0.name) == key })
        else { return false }
        slots[index].doneBy = session
        return true
    }

    /// Sessions deleted for good: their slots are to do again, so the plan
    /// never claims a session History no longer has.
    mutating func reopen(sessions: Set<UUID>) {
        for index in slots.indices where slots[index].doneBy.map(sessions.contains) == true {
            slots[index].doneBy = nil
        }
    }

    /// Every session with this name renamed: so are its slots.
    mutating func rename(key: String, to name: String) {
        for index in slots.indices where SymbolBook.key(for: slots[index].name) == key {
            slots[index].name = ActiveSession.cleanName(name)
        }
    }
}
