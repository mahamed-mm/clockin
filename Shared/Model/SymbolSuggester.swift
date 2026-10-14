import Foundation

/// A first guess at a new name's symbol, from a fixed table of English and
/// Norwegian words. Each word of the name is tried against each rule in
/// order; the first match wins, so "Lekser i matte" is maths rather than
/// study. No model and nothing leaves the phone, and the same name always
/// gets the same guess.
enum SymbolSuggester {
    struct Rule {
        let symbol: String
        /// A word of the name starting with one of these matches.
        var prefixes: [String] = []
        /// Words that match only whole, where a prefix would catch too much
        /// ("les" but not "lesson", "art" but not "article").
        var words: Set<String> = []

        func matches(_ word: String) -> Bool {
            words.contains(word) || prefixes.contains { word.hasPrefix($0) }
        }
    }

    static let rules: [Rule] = [
        Rule(symbol: "flask.fill",
             prefixes: ["chem", "kjemi", "physic", "fysikk", "naturfag", "biolog", "science", "vitenskap"],
             words: ["bio", "lab"]),
        Rule(symbol: "function",
             prefixes: ["math", "matte", "matem", "algebra", "calcul", "kalkul", "statist", "geometr", "trigon"]),
        Rule(symbol: "globe",
             prefixes: ["spanish", "spansk", "french", "fransk", "german", "tysk", "english", "engelsk", "norsk",
                        "norweg", "vocab", "glose", "språk", "language", "japan", "italian", "italiensk", "chinese",
                        "kinesisk", "duolingo"]),
        Rule(symbol: "books.vertical.fill",
             prefixes: ["read", "lese", "lesing", "novel"],
             words: ["les", "bok", "book", "books", "bøker"]),
        Rule(symbol: "graduationcap.fill",
             prefixes: ["study", "studi", "exam", "eksamen", "thesis", "homework", "lekse", "lecture", "forelesning",
                        "revision", "lesson", "leksjon", "master", "bachelor", "course", "kurs"]),
        Rule(symbol: "pencil",
             prefixes: ["writ", "essay", "skriv", "journal", "dagbok", "draft", "utkast", "blog"],
             words: ["stil", "notes", "notater"]),
        Rule(symbol: "chevron.left.forwardslash.chevron.right",
             prefixes: ["code", "coding", "kode", "program", "swift", "python", "javascript", "debug", "refactor",
                        "xcode"],
             words: ["dev", "app", "api", "ios", "git"]),
        Rule(symbol: "briefcase.fill",
             prefixes: ["work", "jobb", "arbeid", "client", "kunde", "report", "rapport", "project", "prosjekt",
                        "office", "kontor"]),
        Rule(symbol: "music.note",
             prefixes: ["music", "musikk", "piano", "guitar", "gitar", "violin", "fiolin", "sing", "synge", "drum",
                        "tromme", "compos", "kompon"],
             words: ["band", "kor", "choir"]),
        Rule(symbol: "paintbrush.pointed.fill",
             prefixes: ["paint", "drawing", "tegn", "sketch", "skisse", "illustr", "kunst"],
             words: ["art", "draw", "male", "maling"]),
        Rule(symbol: "pencil.and.ruler.fill",
             prefixes: ["design", "prototyp", "figma", "wirefram"],
             words: ["ui", "ux"]),
        Rule(symbol: "dumbbell.fill",
             prefixes: ["workout", "trening", "gym", "exercis", "løp", "jogg", "styrke", "strength"],
             words: ["run", "running"]),
        Rule(symbol: "figure.mind.and.body",
             prefixes: ["meditat", "meditas", "yoga", "mindful", "breath", "pust", "avslapp", "relax"]),
        Rule(symbol: "house.fill",
             prefixes: ["clean", "vask", "rydd", "chore", "husarbeid", "laundry", "kles", "tidy"],
             words: ["home", "hjem", "hus"]),
        Rule(symbol: "fork.knife",
             prefixes: ["cook", "matlag", "bake", "baking", "recipe", "oppskrift", "middag", "dinner", "lunch",
                        "lunsj", "meal"],
             words: ["mat"]),
        Rule(symbol: "envelope.fill",
             prefixes: ["email", "mail", "inbox", "innboks", "epost", "admin", "letter", "brev", "correspond"],
             words: ["post"]),
        Rule(symbol: "person.2.fill",
             prefixes: ["meeting", "møte", "interview", "intervju", "standup"],
             words: ["call", "calls"]),
        Rule(symbol: "calendar",
             prefixes: ["planning", "planlegg", "schedule", "agenda", "timeplan"],
             words: ["plan", "week", "uke"]),
        Rule(symbol: "lightbulb.fill",
             prefixes: ["brainstorm", "idédugnad", "idemyldr"],
             words: ["idea", "ideas", "ide", "idé", "ideer"]),
        Rule(symbol: "magnifyingglass",
             prefixes: ["research", "forsk", "investig", "undersøk", "literature", "litteratur"]),
        Rule(symbol: "chart.bar.fill",
             prefixes: ["data", "analys", "analyz", "budget", "budsjett", "excel", "spreadsheet", "regneark",
                        "finance", "økonomi", "accounting", "regnskap"]),
        Rule(symbol: "hammer.fill",
             prefixes: ["build", "bygg", "repair", "repar", "woodwork", "snekr"],
             words: ["fix", "diy"]),
        Rule(symbol: "leaf.fill",
             prefixes: ["garden", "hage", "plant", "nature", "natur"]),
    ]

    /// The symbol a name suggests, or nil when no word matches.
    static func suggest(for name: String) -> String? {
        let words = SymbolBook.key(for: name).split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return nil }
        for rule in rules where words.contains(where: rule.matches) {
            return rule.symbol
        }
        return nil
    }
}
