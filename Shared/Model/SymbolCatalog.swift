import Foundation

/// The symbols a session name can have: a short, curated set that reads
/// well in ink at 12–20 pt. The book is the default and the unnamed
/// session's symbol.
enum SymbolCatalog {
    static let unnamed = "book.closed.fill"

    /// In the picker's order: six rows of four.
    static let ids: [String] = [
        unnamed, "books.vertical.fill", "graduationcap.fill", "pencil",
        "briefcase.fill", "chevron.left.forwardslash.chevron.right", "function", "flask.fill",
        "globe", "music.note", "paintbrush.pointed.fill", "pencil.and.ruler.fill",
        "dumbbell.fill", "figure.mind.and.body", "house.fill", "fork.knife",
        "envelope.fill", "person.2.fill", "calendar", "lightbulb.fill",
        "magnifyingglass", "chart.bar.fill", "hammer.fill", "leaf.fill",
    ]

    private static let known = Set(ids)

    static func contains(_ id: String) -> Bool { known.contains(id) }
}
