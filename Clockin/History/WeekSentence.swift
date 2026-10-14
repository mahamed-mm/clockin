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
/// lengths, a weekday and a part of the day, never what sessions were called.
enum WeekSentence {
    static let instructions = """
        You write one short, calm sentence about someone's week of focus sessions, using only the facts given. \
        At most 15 words. Plain and warm. No advice, no praise, no exclamation marks, no emoji, \
        no streaks or comparisons. Don't invent anything.
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
                                     calendar: calendar, timeZone: calendar.timeZone)
        var lines = [
            "Sessions: \(facts.sessions)",
            "Total focus: \(minutes(facts.totalSeconds))",
            "Longest session: \(minutes(facts.longestSeconds))",
            "Days with focus: \(facts.daysWithFocus)",
            "Busiest day: \(facts.busiestDay.formatted(style.weekday(.wide)))",
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
    /// something that isn't one calm sentence in the app's language.
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
