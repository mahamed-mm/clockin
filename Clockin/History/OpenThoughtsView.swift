import SwiftUI

/// Every parked thought not yet ticked off, by subject, with when it was
/// parked; the cancelled sessions' under their own heading. Ticking one off
/// draws a pen line through it, then it folds away, with Undo.
struct OpenThoughtsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ticked off moments ago: still listed while the line is drawn.
    @State private var folding: Set<UUID> = []
    @State private var copied = false

    var body: some View {
        let open = services.openThoughts(keeping: folding)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(Copy.openThoughtsTitle)
                    .retroFont(.title)
                    .foregroundStyle(Retro.ink)
                    .accessibilityAddTraits(.isHeader)
                ForEach(open.groups) { group in
                    section(group)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
                if open.isEmpty {
                    Text(Copy.noOpenThoughts)
                        .font(.retro(.body))
                        .foregroundStyle(Retro.inkSoft)
                }
                actions(open)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
            .animation(Motion.calm(reduceMotion), value: open)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(PaperBackground().paperGrain())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func section(_ group: OpenThoughts.Group) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                if let key = group.key {
                    Image(systemName: services.symbol(for: group.name))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Retro.inkSoft)
                        .accessibilityHidden(true)
                    Text(Copy.displayName(key.isEmpty ? "" : group.name))
                        .retroLabel()
                } else {
                    Text(Copy.fromCancelledSessions)
                        .retroLabel()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.thoughts) { thought in
                    OpenThoughtRow(thought: thought, struck: thought.done == true,
                                   date: OpenThoughts.dateText(thought.parkedAt, today: services.today,
                                                               calendar: services.calendar)) {
                        toggle(thought)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .background(Retro.ink.opacity(0.06), in: .rect(cornerRadius: Radius.card))
        }
    }

    private func actions(_ open: OpenThoughts) -> some View {
        HStack(spacing: Space.s) {
            if !open.isEmpty {
                Button {
                    UIPasteboard.general.string = open.plainText
                    copied = true
                } label: {
                    Label(copied ? Copy.copied : Copy.copyAll, systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                ShareLink(item: open.plainText) {
                    Label(Copy.share, systemImage: "square.and.arrow.up")
                }
            }
            Spacer(minLength: Space.xs)
            if services.thoughts.hasDone {
                Button(Copy.clearTicked, role: .destructive, action: services.clearTickedThoughts)
                    .foregroundStyle(Retro.rustText)
            }
        }
        .font(.retro(.meta))
        .foregroundStyle(Retro.ink)
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .frame(minHeight: 44)
    }

    /// Ticked off: the line is drawn, then after a beat it folds away. A
    /// second tap while it's still there takes it back.
    private func toggle(_ thought: ParkedThought) {
        if thought.done == true {
            services.setThoughtDone(false, thought.id)
            folding.remove(thought.id)
            return
        }
        let still = reduceMotion || services.power.isConstrained
        folding.insert(thought.id)
        if still {
            services.tickOffThought(thought.id)
        } else {
            withAnimation(.easeInOut(duration: 0.45 * Motion.speed)) { services.tickOffThought(thought.id) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds((still ? 0.6 : 1.05) * Motion.speed))
            withAnimation(services.power.isConstrained ? nil : Motion.calm(reduceMotion)) {
                _ = folding.remove(thought.id)
            }
        }
    }
}

/// One open thought: a circle to tick it off, the text, and when it was
/// parked. Ticked, a pen line runs through it.
struct OpenThoughtRow: View {
    let thought: ParkedThought
    let struck: Bool
    var date: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: struck ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(struck ? Retro.inkSoft : Retro.ink)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(thought.text)
                        .font(.retro(.body))
                        .foregroundStyle(struck ? Retro.inkSoft : Retro.ink)
                        .textRenderer(PenStroke(progress: struck ? 1 : 0, color: Retro.inkSoft))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let date {
                        Text(date)
                            .font(.retro(.meta))
                            .foregroundStyle(Retro.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thought.text)
        .accessibilityValue([struck ? Copy.thoughtDone : nil, date].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(struck ? Copy.markNotDone : Copy.markDone)
        .accessibilityAddTraits(struck ? .isSelected : [])
    }
}

/// "3 open thoughts" at the top of History; hidden when there are none.
struct OpenThoughtsLink: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.xs) {
                Image(systemName: "note.text")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
                Text(Copy.openThoughtsCount(count))
                    .font(.retro(.body))
                    .foregroundStyle(Retro.ink)
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Copy.showsOpenThoughts)
    }
}

extension OpenThoughts {
    /// When a thought was parked: "Today", "Yesterday", "Tuesday", or "3 Oct".
    static func dateText(_ date: Date, today: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: today)).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        case 2..<7: return date.formatted(.dateTime.weekday(.wide))
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}
