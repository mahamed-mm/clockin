import SwiftUI

/// One saved session, opened from its row in History: when it ran, what
/// was recorded, and Rename, Change symbol and Delete in one place.
struct SessionCard: View {
    enum Mode { case viewing, renaming, pickingSymbol }

    let summary: SessionSummary
    let now: Date
    let calendar: Calendar
    /// The name's symbol.
    let symbol: String
    /// Saves a new name.
    let rename: (String) -> Void
    /// Picks the symbol for every session with this name.
    let setSymbol: (String) -> Void
    /// Deletes the session; History offers Undo.
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode
    @State private var draft: String
    @FocusState private var fieldFocused: Bool

    init(summary: SessionSummary, now: Date, calendar: Calendar, symbol: String, opening mode: Mode = .viewing,
         rename: @escaping (String) -> Void, setSymbol: @escaping (String) -> Void, delete: @escaping () -> Void) {
        self.summary = summary
        self.now = now
        self.calendar = calendar
        self.symbol = symbol
        self.rename = rename
        self.setSymbol = setSymbol
        self.delete = delete
        _mode = State(initialValue: mode)
        _draft = State(initialValue: mode == .renaming ? summary.name : "")
    }

    private var renaming: Bool { mode == .renaming }

    var body: some View {
        CardSheet(symbol: symbol, tint: Retro.orangeText, badgeTint: Retro.ink,
                  overline: summary.overline(now: now, calendar: calendar),
                  spokenOverline: summary.spokenOverline(now: now, calendar: calendar)) {
            Group {
                if renaming {
                    TextField(Copy.displayName(""), text: $draft)
                        .retroFont(.title)
                        .foregroundStyle(Retro.ink)
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onSubmit(save)
                        .onChange(of: draft) { _, name in
                            if name.count > ActiveSession.maxNameLength {
                                draft = String(name.prefix(ActiveSession.maxNameLength))
                            }
                        }
                        .accessibilityLabel("Session name")
                } else {
                    Text(summary.title)
                        .retroFont(.title)
                        .foregroundStyle(Retro.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .transition(.opacity)
        } rows: {
            if mode == .pickingSymbol {
                SymbolGrid(selected: symbol) { picked in
                    setSymbol(picked)
                    mode = .viewing
                }
                .padding(Space.s)
            } else {
                ForEach(summary.rows, id: \.self) { row in
                    CardRow(label: row.label, value: row.value)
                }
            }
        } actions: {
            switch mode {
            case .renaming:
                CardAction(title: String(localized: "Save name"), action: save)
                CardAction(title: String(localized: "Cancel"), role: .cancel) { mode = .viewing }
            case .pickingSymbol:
                CardAction(title: String(localized: "Cancel"), role: .cancel) { mode = .viewing }
            case .viewing:
                CardAction(title: String(localized: "Rename")) {
                    draft = summary.name
                    mode = .renaming
                    fieldFocused = true
                }
                if !SymbolBook.key(for: summary.name).isEmpty {
                    CardAction(title: Copy.changeSymbol) { mode = .pickingSymbol }
                }
                CardAction(title: String(localized: "Delete session"), role: .destructive) {
                    dismiss()
                    delete()
                }
            }
        }
        .animation(Motion.calm(reduceMotion), value: mode)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear { if mode == .renaming { fieldFocused = true } }
    }

    private func save() {
        rename(draft)
        dismiss()
    }
}

/// The card in brief, shown while a row's menu is open.
struct SessionPeek: View {
    let summary: SessionSummary
    let now: Date
    let calendar: Calendar
    let symbol: String

    var body: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Retro.ink)
                .frame(width: 44, height: 44)
                .background(Retro.ink.opacity(0.14), in: .circle)
            Text(summary.overline(now: now, calendar: calendar))
                .font(.retro(.label))
                .textCase(.uppercase)
                .tracking(2.2)
                .foregroundStyle(Retro.orangeText)
            Text(summary.title)
                .retroFont(.headline)
                .foregroundStyle(Retro.ink)
                .multilineTextAlignment(.center)
            Text(TimeFormat.duration(summary.focusSeconds))
                .font(.retro(.meta))
                .foregroundStyle(Retro.inkSoft)
        }
        .padding(Space.l)
        .frame(width: 300)
        .background(Retro.paper)
    }
}
