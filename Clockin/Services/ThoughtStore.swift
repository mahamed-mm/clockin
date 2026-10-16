import Foundation

/// Parked thoughts kept after their focus session: with the session they
/// were parked in, by its id, or unfiled when that session was cancelled.
/// Kept apart from History's store, in the app's own folder, so the widget
/// extension never has them; pure, so it can be tested.
struct ThoughtBook: Codable, Equatable, Sendable {
    var bySession: [UUID: [ParkedThought]] = [:]
    /// From cancelled sessions, until ticked off or cleared.
    var unfiled: [ParkedThought] = []

    func thoughts(for session: UUID) -> [ParkedThought] { bySession[session] ?? [] }

    /// Keeps a finished session's thoughts with it; ones already kept stay as they are.
    mutating func file(_ thoughts: [ParkedThought], under session: UUID) {
        guard !thoughts.isEmpty else { return }
        var kept = bySession[session] ?? []
        let known = Set(kept.map(\.id))
        kept += thoughts.filter { !known.contains($0.id) }
        bySession[session] = kept
        unfiled.removeAll { thought in thoughts.contains { $0.id == thought.id } }
    }

    /// A cancelled session's thoughts, kept rather than lost.
    mutating func unfile(_ thoughts: [ParkedThought]) {
        let known = Set(unfiled.map(\.id))
        unfiled += thoughts.filter { !known.contains($0.id) }
    }

    /// Back on their session (Undo after a cancel).
    mutating func takeBack(_ ids: Set<UUID>) {
        unfiled.removeAll { ids.contains($0.id) }
    }

    mutating func setDone(_ done: Bool, thought id: UUID) {
        for (session, thoughts) in bySession {
            if let index = thoughts.firstIndex(where: { $0.id == id }) {
                bySession[session]?[index].done = done
                return
            }
        }
        if let index = unfiled.firstIndex(where: { $0.id == id }) { unfiled[index].done = done }
    }

    mutating func clear(session: UUID) { bySession[session] = nil }

    mutating func clearUnfiled() { unfiled = [] }

    /// Forgets every thought already ticked off, filed or not.
    mutating func clearDone() {
        bySession = bySession.compactMapValues { thoughts in
            let open = thoughts.filter { $0.done != true }
            return open.isEmpty ? nil : open
        }
        unfiled.removeAll { $0.done == true }
    }

    /// Some are ticked off, for Clear ticked.
    var hasDone: Bool {
        unfiled.contains { $0.done == true } || bySession.values.contains { $0.contains { $0.done == true } }
    }


    /// Forgets thoughts of sessions that are gone.
    mutating func prune(keeping sessions: Set<UUID>) {
        bySession = bySession.filter { sessions.contains($0.key) }
    }

    /// Adds a backup's thoughts, by id; nothing kept here is replaced.
    mutating func merge(_ other: ThoughtBook) {
        for (session, thoughts) in other.bySession { file(thoughts, under: session) }
        unfile(other.unfiled.filter { thought in
            !bySession.values.contains { $0.contains { $0.id == thought.id } }
        })
    }
}

protocol ThoughtStoring {
    func load() -> ThoughtBook
    func save(_ book: ThoughtBook)
}

/// A JSON file in Application Support: the app's own, not the App Group's.
struct FileThoughtStore: ThoughtStoring {
    var url: URL = URL.applicationSupportDirectory.appending(path: "parked-thoughts.v1.json")

    func load() -> ThoughtBook {
        guard let data = try? Data(contentsOf: url) else { return ThoughtBook() }
        do {
            return try JSONDecoder().decode(ThoughtBook.self, from: data)
        } catch {
            Log.store.error("Unreadable parked thoughts; starting afresh: \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable"))
            return ThoughtBook()
        }
    }

    func save(_ book: ThoughtBook) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // Readable after the first unlock: Siri can park a thought on a locked phone.
            try JSONEncoder().encode(book).write(to: url, options: [.atomic,
                                                                   .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Log.store.error("Couldn't save parked thoughts: \(error, privacy: .public)")
        }
    }
}

final class InMemoryThoughtStore: ThoughtStoring {
    private var book: ThoughtBook
    init(_ book: ThoughtBook = ThoughtBook()) { self.book = book }
    func load() -> ThoughtBook { book }
    func save(_ book: ThoughtBook) { self.book = book }
}
