import SwiftUI
import TipKit

/// One hint for each thing Clockin doesn't show: Tick's crown, a History
/// row's menu, tapping days and subjects, the name's symbol, the break
/// chips and parking a thought. Each waits until there's been a fair chance
/// to find it alone, shows once, one at a time, never during focus and
/// never before the first session is done.
enum ClockinTips {
    /// A focus phase is running: no tip then.
    @Parameter static var focusRunning: Bool = false
    /// At least one focus session is done: no tip before that.
    @Parameter static var hasFinished: Bool = false

    static let sessionStarted = Tips.Event(id: "sessionStarted")
    static let crownTapped = Tips.Event(id: "crownTapped")
    static let historyOpened = Tips.Event(id: "historyOpened")
    static let rowMenuOpened = Tips.Event(id: "rowMenuOpened")
    static let dayOrSubjectTapped = Tips.Event(id: "dayOrSubjectTapped")
    static let namedSessionStarted = Tips.Event(id: "namedSessionStarted")
    static let symbolPicked = Tips.Event(id: "symbolPicked")
    static let breakStarted = Tips.Event(id: "breakStarted")
    static let breakStyleChosen = Tips.Event(id: "breakStyleChosen")
    static let thoughtParked = Tips.Event(id: "thoughtParked")

    /// Counts a moment a tip waits on.
    static func note(_ event: Tips.Event<Tips.EmptyDonation>) {
        Task { await event.donate() }
    }

    static let all: [any Tip.Type] = [CrownTip.self, SymbolTip.self, HistoryTapTip.self, HistoryMenuTip.self,
                                      BreakChipsTip.self, ParkTip.self]

    /// Set by the debug menu: TipKit can only forget before it's configured.
    static let resetKey = "tips.resetOnLaunch"

    static func configure() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-ResetOnboarding") || defaults.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            defaults.removeObject(forKey: resetKey)
        }
        // `-DemoTip ParkTip`: that tip, whatever its rules, for screenshots.
        if let name = UserDefaults.standard.string(forKey: "DemoTip"),
           let tip = all.first(where: { String(describing: $0) == name }) {
            Tips.showTipsForTesting([tip])
            try? Tips.configure([.displayFrequency(.immediate)])
            return
        }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// Tick's crown starts and pauses: after two starts with the big button.
struct CrownTip: Tip {
    var id: String { "CrownTip" }
    var title: Text { Text(Copy.tipCrownTitle) }
    var message: Text? { Text(Copy.tipCrownMessage) }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] {
        #Rule(ClockinTips.$focusRunning) { $0 == false }
        #Rule(ClockinTips.$hasFinished) { $0 == true }
        #Rule(ClockinTips.sessionStarted) { $0.donations.count >= 2 }
        #Rule(ClockinTips.crownTapped) { $0.donations.count == 0 }
    }
}

/// The name's icon picks a symbol: after three named sessions without picking one.
struct SymbolTip: Tip {
    var id: String { "SymbolTip" }
    var title: Text { Text(Copy.tipSymbolTitle) }
    var message: Text? { Text(Copy.tipSymbolMessage) }
    var image: Image? { Image(systemName: "square.grid.2x2") }
    var rules: [Rule] {
        #Rule(ClockinTips.$focusRunning) { $0 == false }
        #Rule(ClockinTips.$hasFinished) { $0 == true }
        #Rule(ClockinTips.namedSessionStarted) { $0.donations.count >= 3 }
        #Rule(ClockinTips.symbolPicked) { $0.donations.count == 0 }
    }
}

/// Days and subjects can be tapped: after History was opened twice without.
struct HistoryTapTip: Tip {
    var id: String { "HistoryTapTip" }
    var title: Text { Text(Copy.tipHistoryTapTitle) }
    var message: Text? { Text(Copy.tipHistoryTapMessage) }
    var image: Image? { Image(systemName: "hand.point.up.left") }
    var rules: [Rule] {
        #Rule(ClockinTips.$focusRunning) { $0 == false }
        #Rule(ClockinTips.$hasFinished) { $0 == true }
        #Rule(ClockinTips.historyOpened) { $0.donations.count >= 2 }
        #Rule(ClockinTips.dayOrSubjectTapped) { $0.donations.count == 0 }
    }
}

/// A row's long-press menu: after History was opened three times without.
struct HistoryMenuTip: Tip {
    var id: String { "HistoryMenuTip" }
    var title: Text { Text(Copy.tipHistoryMenuTitle) }
    var message: Text? { Text(Copy.tipHistoryMenuMessage) }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] {
        #Rule(ClockinTips.$focusRunning) { $0 == false }
        #Rule(ClockinTips.$hasFinished) { $0 == true }
        #Rule(ClockinTips.historyOpened) { $0.donations.count >= 3 }
        #Rule(ClockinTips.rowMenuOpened) { $0.donations.count == 0 }
    }
}

/// The break chips: on the second break without choosing one.
struct BreakChipsTip: Tip {
    var id: String { "BreakChipsTip" }
    var title: Text { Text(Copy.tipBreakChipsTitle) }
    var message: Text? { Text(Copy.tipBreakChipsMessage) }
    var image: Image? { Image(systemName: "figure.cooldown") }
    var rules: [Rule] {
        #Rule(ClockinTips.$hasFinished) { $0 == true }
        #Rule(ClockinTips.breakStarted) { $0.donations.count >= 2 }
        #Rule(ClockinTips.breakStyleChosen) { $0.donations.count == 0 }
    }
}

/// Parking a thought: at the completion screen, after two sessions without parking one.
struct ParkTip: Tip {
    var id: String { "ParkTip" }
    var title: Text { Text(Copy.tipParkTitle) }
    var message: Text? { Text(Copy.tipParkMessage) }
    var image: Image? { Image(systemName: "note.text") }
    var rules: [Rule] {
        #Rule(ClockinTips.$focusRunning) { $0 == false }
        #Rule(ClockinTips.$hasFinished) { $0 == true }
        #Rule(ClockinTips.sessionStarted) { $0.donations.count >= 2 }
        #Rule(ClockinTips.thoughtParked) { $0.donations.count == 0 }
    }
}

/// Paper, ink and Fraunces, like a card: no system blue.
struct RetroTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            configuration.image?
                .font(.title3.weight(.semibold))
                .foregroundStyle(Retro.orangeText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                configuration.title
                    .retroFont(.headline)
                    .foregroundStyle(Retro.ink)
                configuration.message?
                    .font(.retro(.body))
                    .foregroundStyle(Retro.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(.leading, Space.m)
        .padding(.vertical, Space.xs)
        .background(Retro.paper, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Retro.ink.opacity(0.12)) }
    }
}
