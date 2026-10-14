import Foundation
import Testing
import UIKit
@testable import Clockin

/// The first guess at a name's symbol, in English and Norwegian.
struct SymbolSuggesterTests {
    @Test(arguments: [
        ("Chemistry", "flask.fill"), ("Organic chemistry", "flask.fill"), ("Kjemi", "flask.fill"),
        ("Bio lab", "flask.fill"),
        ("Linear algebra", "function"), ("Matte", "function"), ("Lekser i matte", "function"),
        ("Spanish vocab", "globe"), ("Norsk", "globe"), ("Gloser", "globe"),
        ("Reading: Dune", "books.vertical.fill"), ("Les", "books.vertical.fill"), ("Lesing", "books.vertical.fill"),
        ("Thesis outline", "graduationcap.fill"), ("Eksamen", "graduationcap.fill"), ("Lesson plan", "graduationcap.fill"),
        ("Journaling", "pencil"), ("Skrive stil", "pencil"),
        ("Swift refactor", "chevron.left.forwardslash.chevron.right"),
        ("Client report", "briefcase.fill"), ("Piano practice", "music.note"),
        ("Art", "paintbrush.pointed.fill"), ("UX review", "pencil.and.ruler.fill"),
        ("Trening", "dumbbell.fill"), ("Yoga", "figure.mind.and.body"), ("Rydde", "house.fill"),
        ("Matlaging", "fork.knife"), ("Emails", "envelope.fill"), ("E-post", "envelope.fill"),
        ("Team meeting", "person.2.fill"), ("Week plan", "calendar"), ("Brainstorm", "lightbulb.fill"),
        ("Research", "magnifyingglass"), ("Budsjett", "chart.bar.fill"), ("Fix the bike", "hammer.fill"),
        ("Hagearbeid", "leaf.fill"),
    ])
    func suggests(_ name: String, _ symbol: String) {
        #expect(SymbolSuggester.suggest(for: name) == symbol)
    }

    @Test func wholeWordsDontCatchLongerOnes() {
        #expect(SymbolSuggester.suggest(for: "Article") == nil) // Not "art".
        #expect(SymbolSuggester.suggest(for: "Matador") == nil) // Not "mat".
        #expect(SymbolSuggester.suggest(for: "Identity") == nil) // Not "ide".
    }

    @Test func noGuessForUnknownOrEmptyNames() {
        #expect(SymbolSuggester.suggest(for: "Dune") == nil)
        #expect(SymbolSuggester.suggest(for: "") == nil)
        #expect(SymbolSuggester.suggest(for: "123 !!") == nil)
    }

    @Test func everySuggestionIsOffered() {
        for rule in SymbolSuggester.rules { #expect(SymbolCatalog.contains(rule.symbol), "\(rule.symbol)") }
    }

    @Test func everyOfferedSymbolExistsAndHasASpokenName() {
        for id in SymbolCatalog.ids {
            #expect(UIImage(systemName: id) != nil, "\(id)")
            #expect(!Copy.symbolName(id).isEmpty)
            #expect(Copy.symbolName(id) != id)
        }
    }
}
