import SwiftData
import SwiftUI

extension SetPlan {
    /// Recent names to add with a tap: newest first, leaving out what's
    /// already planned and still to do, and none once the plan is full.
    func suggestions(from recent: [String], limit: Int = 6) -> [String] {
        guard slots.count < Self.capacity else { return [] }
        return Array(recent.filter(canAdd).prefix(limit))
    }
}

/// Plans today's set: up to four names, added from recent names or typed,
/// put in order by dragging (or VoiceOver's Move up and Move down), and
/// removed. Changes are kept when the sheet closes, however it closes.
struct PlanSheet: View {
    let day: Date
    let initial: SetPlan?
    let save: (SetPlan?) -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(PlanSheet.newestFirst) private var records: [FocusRecord]
    @State private var draft: SetPlan
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool
    /// The row being dragged, and how far.
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeight: CGFloat = 52

    init(day: Date, initial: SetPlan?, save: @escaping (SetPlan?) -> Void) {
        self.day = day
        self.initial = initial
        self.save = save
        _draft = State(initialValue: initial ?? SetPlan(day: day))
    }

    private static var newestFirst: FetchDescriptor<FocusRecord> {
        var descriptor = FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var suggestions: [String] {
        draft.suggestions(from: HistoryService.recentNames(records.map(\.name), excluding: "", limit: 12))
    }

    var body: some View {
        CardSheet(symbol: "list.bullet", tint: Retro.orangeText, badgeTint: Retro.ink,
                  overline: [Copy.planOverline]) {
            Text(Copy.planTheSet)
                .retroFont(.title)
                .foregroundStyle(Retro.ink)
                .accessibilityAddTraits(.isHeader)
        } rows: {
            if draft.isEmpty {
                Text(Copy.planHint)
                    .font(.retro(.body))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, Space.m)
            }
            ForEach(Array(draft.slots.enumerated()), id: \.element.id) { index, slot in
                row(slot, index: index)
            }
            if draft.slots.count < SetPlan.capacity {
                addRow
            }
        } actions: {
            CardAction(title: Copy.planDone) { dismiss() }
            if !draft.isEmpty {
                CardAction(title: Copy.clearPlan, role: .destructive) {
                    draft.slots = []
                    dismiss()
                }
            }
        }
        .animation(Motion.calm(reduceMotion), value: draft.slots.map(\.id))
        .onDisappear { save(draft.isEmpty ? nil : draft) }
    }

    // MARK: Rows

    private func row(_ slot: SetPlan.Slot, index: Int) -> some View {
        let isDragged = dragging == slot.id
        return HStack(spacing: Space.s) {
            Image(systemName: services.symbol(for: slot.name))
                .font(.body.weight(.semibold))
                .foregroundStyle(Retro.inkSoft)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(Copy.displayName(slot.name))
                .font(.retro(.body))
                .foregroundStyle(slot.isDone ? Retro.inkSoft : Retro.ink)
                .strikethrough(slot.isDone, color: Retro.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            if slot.isDone {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
            }
            Button {
                draft.remove(id: slot.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Retro.rustText)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(Retro.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .gesture(reorder(slot, from: index))
                .accessibilityHidden(true)
        }
        .padding(.leading, Space.m)
        .frame(minHeight: 52)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = max(44, $0) }
        .background(isDragged ? Retro.ink.opacity(0.06) : .clear)
        .offset(y: isDragged ? dragOffset : 0)
        .zIndex(isDragged ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.planSlotSpoken(slot.name, position: index + 1, of: draft.slots.count,
                                                done: slot.isDone))
        .accessibilityActions {
            if index > 0 {
                Button(Copy.moveUp) { draft.move(fromOffsets: [index], toOffset: index - 1) }
            }
            if index < draft.slots.count - 1 {
                Button(Copy.moveDown) { draft.move(fromOffsets: [index], toOffset: index + 2) }
            }
            Button(Copy.remove) { draft.remove(id: slot.id) }
        }
    }

    /// Dragging a row by its handle: it follows the finger, and drops into
    /// the place nearest to where it's let go.
    private func reorder(_ slot: SetPlan.Slot, from index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragging = slot.id
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let steps = Int((value.translation.height / rowHeight).rounded())
                let target = min(max(0, index + steps), draft.slots.count - 1)
                var still = Transaction(animation: nil)
                still.disablesAnimations = reduceMotion
                withTransaction(still) {
                    if target != index {
                        draft.move(fromOffsets: [index], toOffset: target > index ? target + 1 : target)
                    }
                    dragging = nil
                    dragOffset = 0
                }
            }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                TextField(Copy.addAName, text: $typed)
                    .font(.retro(.body))
                    .foregroundStyle(Retro.ink)
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(addTyped)
                    .onChange(of: typed) { _, name in
                        if name.count > ActiveSession.maxNameLength {
                            typed = String(name.prefix(ActiveSession.maxNameLength))
                        }
                    }
            }
            .frame(minHeight: 48)
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.xs) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { draft.add(name) } label: {
                                HStack(spacing: Space.xxs) {
                                    Image(systemName: services.symbol(for: name))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Retro.inkSoft)
                                        .accessibilityHidden(true)
                                    Text(Copy.displayName(name))
                                        .font(.retro(.meta))
                                        .foregroundStyle(Retro.ink)
                                        .lineLimit(1)
                                }
                                .retroChip()
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Copy.addAName)
                        }
                    }
                    .padding(Space.xxs)
                }
                .scrollIndicators(.hidden)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "Recent names"))
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.xs)
    }

    private func addTyped() {
        if draft.add(typed) { typed = "" }
        // Keep typing: the next name goes straight in.
        fieldFocused = draft.slots.count < SetPlan.capacity
    }
}
