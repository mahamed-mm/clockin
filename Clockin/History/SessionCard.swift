import SwiftUI

/// One saved session, opened from its row in History: when it ran, what
/// was recorded, and Rename and Delete in one place.
struct SessionCard: View {
    let summary: SessionSummary
    let now: Date
    let calendar: Calendar
    /// Saves a new name.
    let rename: (String) -> Void
    /// Deletes the session; History offers Undo.
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        CardSheet(symbol: "book.closed.fill", tint: Retro.orangeText,
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
            ForEach(summary.rows, id: \.self) { row in
                CardRow(label: row.label, value: row.value)
            }
        } actions: {
            if renaming {
                CardAction(title: String(localized: "Save name"), action: save)
                CardAction(title: String(localized: "Cancel"), role: .cancel) { renaming = false }
            } else {
                CardAction(title: String(localized: "Rename")) {
                    draft = summary.name
                    renaming = true
                    fieldFocused = true
                }
                CardAction(title: String(localized: "Delete session"), role: .destructive) {
                    dismiss()
                    delete()
                }
            }
        }
        .animation(Motion.calm(reduceMotion), value: renaming)
        .accessibilityAction(.escape) { dismiss() }
    }

    private func save() {
        rename(draft)
        dismiss()
    }
}
