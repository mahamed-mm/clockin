import Foundation
import Testing
@testable import Clockin

/// Each session name's symbol: how names match, and how picks survive renames and tidying.
struct SymbolBookTests {
    @Test func namesMatchIgnoringCaseWidthAndExtraSpaces() {
        #expect(SymbolBook.key(for: "Chemistry") == "chemistry")
        #expect(SymbolBook.key(for: "  CHEMISTRY ") == "chemistry")
        #expect(SymbolBook.key(for: "Spanish \t vocab") == "spanish vocab")
        #expect(SymbolBook.key(for: "ＡＢＣ") == "abc")
        #expect(SymbolBook.key(for: "   ") == "")
    }

    @Test func norwegianLettersStayApart() {
        #expect(SymbolBook.key(for: "Lås") != SymbolBook.key(for: "Las"))
        #expect(SymbolBook.key(for: "Øving") == "øving")
    }

    @Test func aPickBeatsTheSuggestion() {
        var book = SymbolBook()
        #expect(book.symbol(for: "Thesis outline") == "graduationcap.fill")
        book.pick("pencil", for: "Thesis outline")
        #expect(book.symbol(for: "Thesis outline") == "pencil")
    }

    @Test func aPickShowsForEverySpellingOfTheName() {
        var book = SymbolBook()
        book.pick("flask.fill", for: "Chemistry")
        #expect(book.symbol(for: " chemistry") == "flask.fill")
        #expect(book.symbol(for: "Something else") == SymbolCatalog.unnamed)
        #expect(book.symbol(for: "") == SymbolCatalog.unnamed)
    }

    @Test func onlyOfferedSymbolsArePickedAndUnknownOnesAreKeptButNotShown() {
        var book = SymbolBook()
        book.pick("star.fill", for: "Chemistry")
        #expect(book.picks.isEmpty)
        book.picks["chemistry"] = "symbol.from.a.newer.build"
        #expect(book.symbol(for: "Chemistry") == "flask.fill") // The suggestion.
        #expect(book.picks["chemistry"] == "symbol.from.a.newer.build")
    }

    @Test func renamingCarriesAPickOnlyToANameWithoutOne() {
        var book = SymbolBook()
        book.pick("flask.fill", for: "Chemsitry")
        book.pick("globe", for: "Spanish")

        book.rename(from: "Chemsitry", to: "Chemistry")
        #expect(book.symbol(for: "Chemistry") == "flask.fill")
        #expect(book.symbol(for: "Chemsitry") == "flask.fill") // Its other sessions keep it.

        book.rename(from: "Chemistry", to: "Spanish")
        #expect(book.symbol(for: "Spanish") == "globe")

        book.rename(from: "Chemistry", to: "")
        #expect(book.picks.count == 3)
    }

    @Test func pruningKeepsOnlyNamesStillInUse() {
        var book = SymbolBook()
        book.pick("flask.fill", for: "Chemistry")
        book.pick("globe", for: "Spanish")
        book.prune(keeping: ["CHEMISTRY", "Essay"])
        #expect(book.picks == ["chemistry": "flask.fill"])
    }

    @Test func mergingNeverOverwritesALocalPick() {
        var book = SymbolBook()
        book.pick("pencil", for: "Chemistry")
        book.merge(["Chemistry": "flask.fill", " Spanish ": "globe", "": "globe",
                    "Long": String(repeating: "x", count: 200)])
        #expect(book.picks == ["chemistry": "pencil", "spanish": "globe"])
    }

    @Test func savesAndLoadsThroughDefaults() throws {
        let suite = "SymbolBookTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsSymbolBookStore(defaults: defaults)
        #expect(store.load() == SymbolBook())

        var book = SymbolBook()
        book.pick("flask.fill", for: "Chemistry")
        store.save(book)
        #expect(store.load() == book)

        defaults.set(Data("not json".utf8), forKey: store.key)
        #expect(store.load() == SymbolBook())
    }

    @Test func everyOfferedSymbolIsUnique() {
        #expect(SymbolCatalog.ids.count == 24)
        #expect(Set(SymbolCatalog.ids).count == SymbolCatalog.ids.count)
        #expect(SymbolCatalog.ids.first == SymbolCatalog.unnamed)
    }
}
