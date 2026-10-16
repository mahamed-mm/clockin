import SwiftUI

/// Renames a subject everywhere: every session with the name, the one
/// running now, today's plan and the name field. A name another subject
/// already has asks first, as the two become one. History offers Undo.
struct RenameSubjectSheet: View {
    let key: String
    let name: String
    /// How many sessions have the name.
    let sessions: Int
    let symbol: String
    /// Told the new name once it's done.
    let renamed: (String) -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: String
    /// The other subject the draft would merge into, waiting for a yes.
    @State private var merging: String?
    @FocusState private var fieldFocused: Bool

    init(key: String, name: String, sessions: Int, symbol: String, renamed: @escaping (String) -> Void) {
        self.key = key
        self.name = name
        self.sessions = sessions
        self.symbol = symbol
        self.renamed = renamed
        _draft = State(initialValue: name)
    }

    private var cleaned: String { ActiveSession.cleanName(draft) }
    private var canSave: Bool { !SymbolBook.key(for: cleaned).isEmpty && cleaned != name }

    var body: some View {
        CardSheet(symbol: symbol, tint: Retro.orangeText, badgeTint: Retro.ink, overline: [Copy.renameEverywhere]) {
            if let merging {
                Text(Copy.mergeTitle(merging))
                    .retroFont(.title)
                    .foregroundStyle(Retro.ink)
                    .accessibilityAddTraits(.isHeader)
            } else {
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
                    .accessibilityLabel(Copy.renameEverywhere)
            }
        } rows: {
            Text(merging.map { Copy.mergeNote(sessions, from: name, into: $0) } ?? Copy.renameEverywhereNote(sessions))
                .font(.retro(.body))
                .foregroundStyle(Retro.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
        } actions: {
            if merging != nil {
                CardAction(title: Copy.merge, action: commit)
            } else {
                CardAction(title: String(localized: "Save name"), action: save)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
            }
            CardAction(title: String(localized: "Cancel"), role: .cancel) { dismiss() }
        }
        .animation(Motion.calm(reduceMotion), value: merging)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear { fieldFocused = true }
    }

    /// Straight through, or first the question when it would merge.
    private func save() {
        guard canSave else { return }
        if services.mergesInto(cleaned, from: key) {
            fieldFocused = false
            merging = cleaned
        } else {
            commit()
        }
    }

    private func commit() {
        if services.renameSubject(key: key, to: cleaned) { renamed(cleaned) }
        dismiss()
    }
}

/// Picks the symbol every session of a subject shows.
struct SubjectSymbolSheet: View {
    let name: String
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let symbol = services.symbol(for: name)
        CardSheet(symbol: symbol, tint: Retro.orangeText, badgeTint: Retro.ink, overline: [Copy.changeSymbol]) {
            Text(Copy.displayName(name))
                .retroFont(.title)
                .foregroundStyle(Retro.ink)
                .accessibilityAddTraits(.isHeader)
        } rows: {
            SymbolGrid(selected: symbol) { picked in
                services.setSymbol(picked, for: name)
                dismiss()
            }
            .padding(Space.s)
        } actions: {
            CardAction(title: String(localized: "Cancel"), role: .cancel) { dismiss() }
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}
