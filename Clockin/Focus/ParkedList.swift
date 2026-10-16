import SwiftUI
import UIKit

/// The thoughts parked during focus, to deal with now or later: tick them
/// off, copy or share them all, or clear them. Kept with the session unless
/// cleared.
struct ParkedList: View {
    let thoughts: [ParkedThought]
    var title: String = Copy.parkedThoughts
    let toggle: (ParkedThought) -> Void
    let clear: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .retroLabel()
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(thoughts) { thought in
                    row(thought)
                }
            }
            HStack(spacing: Space.s) {
                Button {
                    UIPasteboard.general.string = Self.plainText(thoughts)
                    copied = true
                } label: {
                    Label(copied ? Copy.copied : Copy.copyAll, systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                ShareLink(item: Self.plainText(thoughts)) {
                    Label(Copy.share, systemImage: "square.and.arrow.up")
                }
                Spacer(minLength: Space.xs)
                Button(Copy.clear, role: .destructive, action: clear)
                    .foregroundStyle(Retro.rustText)
            }
            .font(.retro(.meta))
            .foregroundStyle(Retro.ink)
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .frame(minHeight: 44)
        }
        .padding(Space.m)
        .background(Retro.ink.opacity(0.06), in: .rect(cornerRadius: Radius.card))
        .animation(Motion.calm(reduceMotion), value: thoughts)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func row(_ thought: ParkedThought) -> some View {
        let done = thought.done == true
        return Button { toggle(thought) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Retro.inkSoft : Retro.ink)
                    .contentTransition(.symbolEffect(.replace))
                Text(thought.text)
                    .font(.retro(.body))
                    .foregroundStyle(done ? Retro.inkSoft : Retro.ink)
                    .strikethrough(done, color: Retro.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(thought.text)
        .accessibilityValue(done ? Copy.thoughtDone : "")
        .accessibilityHint(done ? Copy.markNotDone : Copy.markDone)
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    /// "Buy milk", one per line, as copied and shared.
    nonisolated static func plainText(_ thoughts: [ParkedThought]) -> String {
        thoughts.map { ($0.done == true ? "✓ " : "") + $0.text }.joined(separator: "\n")
    }
}

/// The thoughts parked in the session just finished, folded into one quiet
/// row that opens into the list in place, so the
/// completion screen keeps its room. "2 parked", as on the session.
struct ParkedRow: View {
    let thoughts: [ParkedThought]
    let toggle: (ParkedThought) -> Void
    let clear: () -> Void
    /// Opened into the list; kept by the screen, so it stays open when the layout around it changes.
    @Binding var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if open {
            ParkedList(thoughts: thoughts, toggle: toggle, clear: clear)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        } else {
            Button {
                withAnimation(Motion.calm(reduceMotion)) { open = true }
            } label: {
                Label {
                    HStack(spacing: Space.xxs) {
                        Text(Copy.parked(thoughts.count))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Retro.inkSoft)
                            .accessibilityHidden(true)
                    }
                } icon: {
                    Image(systemName: "note.text")
                }
                .font(.retro(.meta).weight(.semibold))
                .foregroundStyle(Retro.ink)
                .retroChip()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.parkedSpoken(thoughts.count))
            .accessibilityHint(Copy.showsParked)
            .transition(.opacity)
        }
    }
}

/// A session's kept thoughts on its card in History.
struct CardThoughts: View {
    let thoughts: [ParkedThought]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(Copy.parkedThoughts)
                .font(.retro(.body))
                .foregroundStyle(Retro.inkSoft)
            ForEach(thoughts) { thought in
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Image(systemName: thought.done == true ? "checkmark" : "circle.fill")
                        .font(.caption2.weight(.semibold))
                        .imageScale(thought.done == true ? .medium : .small)
                        .foregroundStyle(Retro.inkSoft)
                        .accessibilityHidden(true)
                    Text(thought.text)
                        .font(.retro(.body))
                        .foregroundStyle(Retro.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(thought.done == true ? Copy.thoughtDone : "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }
}
