import SwiftUI

/// A total drawn big, in the words `TimeFormat.duration` uses everywhere
/// else: Fraunces digits with small unit labels, "1 h 15 min". The
/// localized text is split into digits and units, so it works in every
/// language. It shrinks evenly to fit; `stacks` puts hours over minutes
/// instead where there's height to spare (StandBy's dial).
struct DurationText: View {
    let seconds: TimeInterval
    var size: CGFloat = 40
    var stacks = false
    /// What VoiceOver reads; the duration in words unless given.
    var spoken: String?
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        let parts = TimeFormat.durationParts(seconds)
        Group {
            if stacks {
                ViewThatFits(in: .horizontal) {
                    line(parts)
                    VStack(spacing: 0) {
                        ForEach(Array(Self.lines(parts).enumerated()), id: \.offset) { _, parts in line(parts) }
                    }
                }
            } else {
                line(parts)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? TimeFormat.spokenDuration(TimeFormat.shownSeconds(seconds)))
    }

    private func line(_ parts: [TimeFormat.DurationPart]) -> some View {
        Text(Self.attributed(parts, size: size, bold: legibilityWeight == .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// Digits in Fraunces Display at `size`; units at half that, softer.
    static func attributed(_ parts: [TimeFormat.DurationPart], size: CGFloat, bold: Bool) -> AttributedString {
        var text = AttributedString()
        for part in parts {
            var run = AttributedString(part.text)
            if part.isNumber {
                run.font = .retroDisplay(size: size)
                run.foregroundColor = Retro.ink
                run.tracking = -1
            } else {
                run.font = .retroFixed(bold ? .title : .text, size: size / 2)
                run.foregroundColor = Retro.inkSoft
            }
            text += run
        }
        return text
    }

    /// One line per number and its unit: "1 h", "15 min".
    static func lines(_ parts: [TimeFormat.DurationPart]) -> [[TimeFormat.DurationPart]] {
        var lines: [[TimeFormat.DurationPart]] = []
        for part in parts {
            let trimmed = TimeFormat.DurationPart(text: part.text.trimmingCharacters(in: .whitespaces),
                                                  isNumber: part.isNumber)
            if part.isNumber || lines.isEmpty {
                lines.append([trimmed])
            } else {
                lines[lines.count - 1].append(TimeFormat.DurationPart(text: " " + trimmed.text, isNumber: false))
            }
        }
        return lines
    }
}
