import Foundation

/// The parked thoughts not yet ticked off, gathered by subject: each
/// subject's thoughts under its name, the subject with the latest thought
/// first, and the cancelled sessions' under their own heading, last. Pure,
/// so it can be tested.
struct OpenThoughts: Equatable {
    struct Group: Equatable, Identifiable {
        /// `SymbolBook.key`, or nil for the cancelled sessions' thoughts.
        var key: String?
        /// As the newest of its sessions spells it.
        var name: String
        var thoughts: [ParkedThought]

        var id: String { key.map { "subject:" + $0 } ?? "unfiled" }
    }

    var groups: [Group]

    /// `names` are the thoughts' sessions' names, by id. A session without
    /// one (gone, or waiting in a delete's Undo) is left out. `keeping`
    /// thoughts stay listed though ticked off: they're folding away.
    init(book: ThoughtBook, names: [UUID: String], keeping: Set<UUID> = []) {
        func isShown(_ thought: ParkedThought) -> Bool { thought.done != true || keeping.contains(thought.id) }

        var bySubject: [String: (name: String, newest: Date, thoughts: [ParkedThought])] = [:]
        for (session, thoughts) in book.bySession {
            guard let name = names[session] else { continue }
            let shown = thoughts.filter(isShown)
            guard !shown.isEmpty else { continue }
            let key = SymbolBook.key(for: name)
            let newest = shown.map(\.parkedAt).max() ?? .distantPast
            var entry = bySubject[key] ?? (name, newest, [])
            if newest >= entry.newest { entry.name = name }
            entry.newest = max(entry.newest, newest)
            entry.thoughts += shown
            bySubject[key] = entry
        }
        groups = bySubject.sorted { $0.value.newest > $1.value.newest }.map { key, entry in
            Group(key: key, name: entry.name, thoughts: entry.thoughts.sorted { $0.parkedAt > $1.parkedAt })
        }
        let unfiled = book.unfiled.filter(isShown)
        if !unfiled.isEmpty {
            groups.append(Group(key: nil, name: "", thoughts: unfiled.sorted { $0.parkedAt > $1.parkedAt }))
        }
    }

    /// How many are still open (not counting ones folding away).
    var openCount: Int { groups.reduce(0) { $0 + $1.thoughts.filter { $0.done != true }.count } }
    var isEmpty: Bool { groups.isEmpty }

    /// Every open thought, one per line, as Copy all and Share give them.
    var plainText: String {
        ParkedList.plainText(groups.flatMap(\.thoughts).filter { $0.done != true })
    }
}
