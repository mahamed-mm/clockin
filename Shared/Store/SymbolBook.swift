import Foundation

/// The symbol each session name shows. Only symbols the user picked are
/// saved, keyed by the name folded for case and width, so "Chemistry" and
/// " chemistry " share one. It lives in the App Group's defaults, where the
/// widget and Live Activity can read it without opening the store.
struct SymbolBook: Codable, Equatable {
    /// Picked symbols, by `key(for:)`.
    var picks: [String: String] = [:]

    /// The name as it's matched: cleaned, case and width folded, and with
    /// runs of spaces made one. Accents stay, as å, ø and æ are letters of
    /// their own in Norwegian. Empty for an unnamed session.
    static func key(for name: String) -> String {
        ActiveSession.cleanName(name)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The symbol to show for a name: the pick, or the book. A pick this
    /// build doesn't know (from a newer one) is kept but not shown.
    func symbol(for name: String) -> String {
        let key = Self.key(for: name)
        guard !key.isEmpty else { return SymbolCatalog.unnamed }
        if let pick = picks[key], SymbolCatalog.contains(pick) { return pick }
        return SymbolCatalog.unnamed
    }

    /// Picks `symbol` for every session with this name. An unnamed session
    /// keeps the book.
    mutating func pick(_ symbol: String, for name: String) {
        let key = Self.key(for: name)
        guard !key.isEmpty, SymbolCatalog.contains(symbol) else { return }
        picks[key] = symbol
    }

    /// A session renamed from `old` to `new`: the symbol belongs to the
    /// name, so it shows the new name's. A new name with no pick of its own
    /// takes the old one's, as a rename is usually a typo fixed.
    mutating func rename(from old: String, to new: String) {
        let from = Self.key(for: old), to = Self.key(for: new)
        guard !to.isEmpty, from != to, picks[to] == nil, let pick = picks[from] else { return }
        picks[to] = pick
    }

    /// Forgets picks for names no session has any more.
    mutating func prune(keeping names: some Sequence<String>) {
        let kept = Set(names.map(Self.key(for:)))
        picks = picks.filter { kept.contains($0.key) }
    }

    /// Adds a backup's picks for names without one here: what's picked on
    /// this phone wins, so restoring twice changes nothing.
    mutating func merge(_ restored: [String: String]) {
        for (name, symbol) in restored where symbol.count <= Self.longestSymbol {
            let key = Self.key(for: name)
            if !key.isEmpty, picks[key] == nil { picks[key] = symbol }
        }
    }

    /// SF Symbols names are short; anything longer isn't one.
    private static let longestSymbol = 80
}

protocol SymbolBookStoring {
    func load() -> SymbolBook
    func save(_ book: SymbolBook)
}

struct DefaultsSymbolBookStore: SymbolBookStoring {
    var defaults: UserDefaults = SharedStore.defaults
    var key = "symbols.v1"

    func load() -> SymbolBook {
        guard let data = defaults.data(forKey: key) else { return SymbolBook() }
        do {
            return try JSONDecoder().decode(SymbolBook.self, from: data)
        } catch {
            Log.store.error("Unreadable symbols; showing defaults: \(error, privacy: .public)")
            return SymbolBook()
        }
    }

    func save(_ book: SymbolBook) {
        do {
            defaults.set(try JSONEncoder().encode(book), forKey: key)
        } catch {
            Log.store.error("Couldn't save symbols: \(error, privacy: .public)")
        }
    }
}

final class InMemorySymbolBookStore: SymbolBookStoring {
    var book: SymbolBook

    init(_ book: SymbolBook = SymbolBook()) {
        self.book = book
    }

    func load() -> SymbolBook { book }
    func save(_ book: SymbolBook) { self.book = book }
}
