import FoundationModels
import NaturalLanguage
import SwiftUI

/// Something that can write the week's line: Apple's on-device model, or a
/// stand-in in tests.
protocol WeekSentenceWriting: Sendable {
    var isAvailable: Bool { get }
    func write(prompt: String, instructions: String) async throws -> String
}

/// The week's line, written by the on-device model when it can, and the
/// fixed sentence otherwise. The model only ever sees `WeekFacts`: counts,
/// lengths, weekdays and a part of the day, never what sessions were called.
enum WeekSentence {
    static let instructions = """
        You write one short, calm sentence about someone's week of focus sessions, using only the facts given. \
        At most 15 words. Plain and warm. No advice, no praise, no exclamation marks, no emoji, \
        no streaks or comparisons. Don't invent anything: name only the days listed as days with focus.
        """

    /// The instructions for a line in `language` (the app's, such as "en"
    /// or "nb"): the facts stay in plain English, the line comes back in the
    /// language the rest of the screen is in.
    static func instructions(language: String) -> String {
        switch language {
        case "en": instructions
        case "nb": instructions + " Write the sentence in Norwegian Bokmål."
        default: instructions
        }
    }

    /// The language the app is showing: one Clockin has, picked from the phone's.
    static var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The language a line reads as, by Apple's on-device recognizer.
    static func dominantLanguage(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    /// The facts as the model reads them.
    static func prompt(for facts: WeekFacts, calendar: Calendar) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en"),
                                     calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
        let days = facts.focusDays.map { $0.formatted(style) }.joined(separator: ", ")
        var lines = [
            "Sessions: \(facts.sessions)",
            "Total focus: \(minutes(facts.totalSeconds))",
            "Longest session: \(minutes(facts.longestSeconds))",
            "Days with focus: \(facts.daysWithFocus) (\(days))",
            "Busiest day: \(facts.busiestDay.formatted(style))",
        ]
        if let part = facts.mostlyIn {
            lines.append("Mostly in the \(part.rawValue)")
        } else if facts.sessions > 1 {
            lines.append("Spread across the day")
        } else {
            lines.append("In the \(facts.firstPart.rawValue)")
        }
        return lines.joined(separator: "\n")
    }

    /// Plain English for the model, whatever the phone's language.
    private static func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) minutes"
    }

    /// The model's line if it's one short sentence, tidied; nil otherwise.
    static func validate(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 120, !text.contains(where: \.isNewline),
              !text.contains("!"), !text.contains("?") else { return nil }
        if !text.hasSuffix(".") { text += "." }
        // One sentence: no full stop before the last.
        guard !text.dropLast().contains(".") else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Whether the line keeps to the facts: every weekday it names had focus,
    /// and every number of days or sessions it gives is the week's. Read in
    /// English, the facts' language, and in `language`, the line's.
    static func keepsToFacts(_ line: String, _ facts: WeekFacts, calendar: Calendar,
                             language: String) -> Bool {
        let words = line.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
        let focusWeekdays = Set(facts.focusDays.map { calendar.component(.weekday, from: $0) })
        for vocabulary in [Vocabulary.english, Vocabulary.for(language)].compactMap(\.self) {
            var named = calendar
            named.locale = Locale(identifier: vocabulary.language)
            // weekdaySymbols starts on Sunday, weekday 1, whatever the first day of the week.
            for (index, day) in named.weekdaySymbols.enumerated() where !focusWeekdays.contains(index + 1) {
                // "Friday", "Fridays", "fredagen": any word that starts with the day.
                if words.contains(where: { $0.hasPrefix(day.lowercased()) }) { return false }
            }
            for (index, word) in words.enumerated() {
                guard let number = Int(word) ?? vocabulary.numbers[word] else { continue }
                // The noun right after the number, or after one word between ("3 long sessions"),
                // but not past a unit ("a 25-minute session" counts minutes, not sessions).
                for noun in words.dropFirst(index + 1).prefix(2) {
                    if vocabulary.days.contains(noun) {
                        if number != facts.daysWithFocus { return false }
                        break
                    }
                    if noun.contains(vocabulary.session) {
                        if number != facts.sessions { return false }
                        break
                    }
                    if Vocabulary.isUnit(noun) { break }
                }
            }
        }
        return true
    }

    /// The words `keepsToFacts` reads numbers of days and sessions by.
    private struct Vocabulary {
        var language: String
        var numbers: [String: Int]
        var days: Set<String>
        /// In every form of the word: "sessions", "fokusøkter".
        var session: String

        static let english = Vocabulary(
            language: "en",
            numbers: ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                      "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12],
            days: ["day", "days"],
            session: "session")

        static let norwegian = Vocabulary(
            language: "nb",
            numbers: ["en": 1, "én": 1, "ett": 1, "ei": 1, "to": 2, "tre": 3, "fire": 4, "fem": 5, "seks": 6,
                      "sju": 7, "syv": 7, "åtte": 8, "ni": 9, "ti": 10, "elleve": 11, "tolv": 12],
            days: ["dag", "dager", "dagar", "fokusdag", "fokusdager"],
            session: "økt")

        /// The vocabulary for a language other than English, when Clockin has it.
        static func `for`(_ language: String) -> Vocabulary? {
            language == "nb" ? norwegian : nil
        }

        /// Minutes and hours, which a number can count instead.
        static func isUnit(_ word: String) -> Bool {
            ["min", "minut", "hour", "time"].contains { word.hasPrefix($0) }
        }
    }

    /// What the line says: the model's sentence when it's allowed, able and
    /// sensible, or the fixed one.
    static func line(for facts: WeekFacts, calendar: Calendar, writer: any WeekSentenceWriting,
                     enabled: Bool, language: String = "en",
                     recognize: (String) -> String? = dominantLanguage(of:)) async -> String {
        guard enabled, let written = await written(for: facts, calendar: calendar, writer: writer, language: language,
                                                   recognize: recognize) else {
            return Copy.weekSentence(facts, calendar: calendar)
        }
        return written
    }

    /// The model's sentence, or nil when it can't write one, or writes
    /// something that isn't one calm, true sentence in the app's language.
    static func written(for facts: WeekFacts, calendar: Calendar, writer: any WeekSentenceWriting,
                        language: String = "en",
                        recognize: (String) -> String? = dominantLanguage(of:)) async -> String? {
        guard writer.isAvailable else { return nil }
        do {
            let written = try await writer.write(prompt: prompt(for: facts, calendar: calendar),
                                                 instructions: instructions(language: language))
            guard let line = validate(written) else {
                Log.store.info("Week line not one calm sentence; using the fixed one: \(written, privacy: .private)")
                return nil
            }
            guard keepsToFacts(line, facts, calendar: calendar, language: language) else {
                Log.store.info("Week line strays from the facts; using the fixed one: \(line, privacy: .private)")
                return nil
            }
            // Not in English, it must read as the app's language; otherwise the fixed line, translated.
            if language != "en", recognize(line) != language {
                Log.store.info("Week line not in \(language, privacy: .public); using the fixed one")
                return nil
            }
            return line
        } catch {
            Log.store.error("Couldn't write the week line: \(error, privacy: .public)")
            return nil
        }
    }
}

/// Apple's on-device language model. Available only on Apple Intelligence
/// iPhones with it turned on, in a language it speaks.
struct OnDeviceWeekWriter: WeekSentenceWriting {
    var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.isAvailable && model.supportsLocale()
    }

    func write(prompt: String, instructions: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt, generating: GeneratedWeekLine.self).content.sentence
    }
}

@Generable
private struct GeneratedWeekLine {
    @Guide(description: "One calm sentence of at most 15 words, with no advice, praise or exclamation marks")
    var sentence: String
}

/// The line under the week strip. The fixed sentence shows at once; a
/// written one fades in when it's ready, and is remembered while the app runs.
struct WeekSentenceLine: View {
    let facts: WeekFacts
    let calendar: Calendar
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var written: String?

    /// Lines already written this run, by what they were written from.
    @MainActor private static var cache: [String: String] = [:]

    var body: some View {
        let language = WeekSentence.appLanguage
        let key = language + "|" + WeekSentence.prompt(for: facts, calendar: calendar)
        Text(written ?? Copy.weekSentence(facts, calendar: calendar))
            .font(.retro(.meta))
            .foregroundStyle(Retro.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.m)
            .contentTransition(.opacity)
            .task(id: "\(key)|\(services.settings.weekSummaries)") {
                guard services.settings.weekSummaries else {
                    written = nil
                    return
                }
                if let cached = Self.cache[key] {
                    written = cached
                    return
                }
                // Only a written line is kept, so a model that wasn't ready yet
                // gets another go next time.
                guard let line = await WeekSentence.written(for: facts, calendar: calendar,
                                                            writer: services.weekWriter, language: language),
                      !Task.isCancelled else { return }
                Self.cache[key] = line
                withAnimation(Motion.calm(reduceMotion)) { written = line }
            }
    }
}
