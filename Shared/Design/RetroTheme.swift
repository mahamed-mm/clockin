import SwiftUI

/// Warm 70s analog palette and type. Colors come from the asset catalog
/// and each has a dark-mode variant.
enum Retro {
    static let paper = Color("Paper")
    static let paperDeep = Color("PaperDeep")
    static let ink = Color("Ink")
    static let inkSoft = Color("InkSoft")
    static let orange = Color("BurntOrange")
    static let mustard = Color("Mustard")
    static let avocado = Color("Avocado")
    static let rust = Color("Rust")

    /// The four stripe colors, warmest last.
    static let stripes: [Color] = [avocado, mustard, orange, rust]

    static func tint(for phase: SessionPhase) -> Color {
        phase == .focus ? orange : avocado
    }

    /// Second gradient stop for a phase's arc.
    static func glow(for phase: SessionPhase) -> Color {
        phase == .focus ? mustard : mustard.opacity(0.85)
    }
}

// MARK: - Typography

/// The type scale. Serif (New York) carries the voice; rounded sans handles
/// labels and numbers. All system fonts, so nothing is bundled.
enum RetroText {
    /// Phase titles: "Focus", "Break", "History".
    case title
    /// Session names and completion lines.
    case headline
    /// Spaced-out appliance labels.
    case label
    /// Time ranges, "ends at", small stats.
    case meta
    /// Fields and rows.
    case body
    /// Large numbers outside the dial (History total, widget minutes).
    case number
}

extension Font {
    static func retro(_ style: RetroText) -> Font {
        switch style {
        case .title: .system(.largeTitle, design: .serif).weight(.bold)
        case .headline: .system(.title3, design: .serif).weight(.semibold)
        case .label: .system(.caption, design: .rounded).weight(.bold)
        case .meta: .system(.subheadline, design: .rounded).weight(.medium).monospacedDigit()
        case .body: .system(.body, design: .rounded).weight(.medium)
        case .number: .system(.largeTitle, design: .serif).weight(.black).monospacedDigit()
        }
    }

    /// The countdown: New York black with monospaced digits.
    static func retroDisplay(size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif).monospacedDigit()
    }
}

extension View {
    /// Small caps-style appliance label.
    func retroLabel() -> some View {
        font(.retro(.label))
            .textCase(.uppercase)
            .tracking(2.2)
            .foregroundStyle(Retro.inkSoft)
    }

    /// Numbers that roll when they change.
    func retroNumber(countsDown: Bool = false) -> some View {
        monospacedDigit()
            .contentTransition(.numericText(countsDown: countsDown))
    }
}

// MARK: - Surfaces

/// Paper background with a soft warm vignette and an optional phase wash.
struct PaperBackground: View {
    var wash: Color? = nil

    var body: some View {
        ZStack {
            Retro.paper
            RadialGradient(colors: [Retro.paperDeep.opacity(0), Retro.paperDeep.opacity(0.9)],
                           center: .center, startRadius: 120, endRadius: 700)
            if let wash {
                RadialGradient(colors: [wash.opacity(0.16), wash.opacity(0)],
                               center: .top, startRadius: 0, endRadius: 520)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Time formatting

enum TimeFormat {
    /// "24:59"
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// "12 minutes 30 seconds remaining"
    static func spoken(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = total >= 60 ? [.minute, .second] : [.second]
        return (formatter.string(from: TimeInterval(total)) ?? "") + " remaining"
    }

    /// Wall-clock time in the user's format: "14:30" or "2:30 PM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "14:05 → 14:30"
    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start)) → \(time(end))"
    }

    /// "25 min", "1 h 15 min", "2 h" ("10 s" under a minute, for test timers)
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "\(Int(seconds)) s" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
