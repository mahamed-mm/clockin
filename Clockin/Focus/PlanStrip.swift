import SwiftData
import SwiftUI

/// Today's plan under the name field, in place of the recent names: one
/// small chip per slot in order, done ones ticked in soft ink, the one in
/// the field picked out like a chosen length. A tap on one still to do puts
/// it in the field. The plan's button stays put in front, where "Plan the
/// set" is among the recent names, so a full plan never scrolls it away.
/// While the name is being typed, the recent names take the chips' place.
/// No set colours: a plan's order isn't the set's.
struct PlanStrip: View {
    let plan: SetPlan
    /// The name in the field.
    let typed: String
    /// The name field has the keyboard.
    var fieldFocused = false
    /// Where each slot's name is, in global space: where a name moving
    /// into the field starts from.
    var report: (UUID, CGRect) -> Void = { _, _ in }
    let pick: (SetPlan.Slot) -> Void
    /// A recent name, tapped while typing.
    var pickRecent: (String) -> Void = { _ in }
    let edit: () -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(RecentNames.newestFirst) private var records: [FocusRecord]

    enum ChipState: Equatable { case done, inField, toDo }

    /// Pure, for the tests: how a slot shows. Of several slots with the
    /// name in the field, only the first still to do is in it: the one a
    /// session with that name ticks.
    static func state(of slot: SetPlan.Slot, in plan: SetPlan, typed: String) -> ChipState {
        if slot.isDone { return .done }
        return plan.firstToDo(named: typed)?.id == slot.id ? .inField : .toDo
    }

    /// Whether a tap on the slot puts it in the field: not when it's done,
    /// or when its name is there already (a later "Thesis" after the first).
    static func canPick(_ slot: SetPlan.Slot, typed: String) -> Bool {
        let key = SymbolBook.key(for: typed)
        return !slot.isDone && (key.isEmpty || SymbolBook.key(for: slot.name) != key)
    }

    /// The strip read aloud as one line: "Today's plan: Chemistry, done;
    /// Thesis outline, up next; Linear algebra".
    static func spoken(_ plan: SetPlan, typed: String) -> String {
        let parts = plan.slots.map { slot in
            switch state(of: slot, in: plan, typed: typed) {
            case .done: "\(Copy.displayName(slot.name)), \(Copy.planDone.lowercased())"
            case .inField: "\(Copy.displayName(slot.name)), \(Copy.planInField.lowercased())"
            case .toDo: Copy.displayName(slot.name)
            }
        }
        return Copy.todaysPlan + ": " + parts.joined(separator: "; ")
    }

    var body: some View {
        let recent = RecentNames.names(records, typed: typed)
        let showsRecent = FocusLayout.showsRecentNames(fieldFocused: fieldFocused, hasRecent: !recent.isEmpty)
        HStack(spacing: Space.xs) {
            editButton
            ScrollView(.horizontal) {
                // Both rows are chips of one height, so swapping them never
                // moves the dial.
                HStack(spacing: Space.xs) {
                    if showsRecent {
                        ForEach(recent, id: \.self) { name in
                            RecentNameChip(name: name) { pickRecent(name) }
                        }
                    } else {
                        ForEach(plan.slots) { slot in
                            chip(slot)
                        }
                    }
                }
                .padding(.vertical, Space.xxs)
                .padding(.trailing, Space.xxs)
                .id(showsRecent)
                .transition(.opacity)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.leading, Space.xxs)
        .animation(Motion.calm(reduceMotion), value: showsRecent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(showsRecent ? String(localized: "Recent names") : Copy.todaysPlan)
    }

    private var editButton: some View {
        Button(action: edit) {
            Image(systemName: "list.bullet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Retro.ink)
                .frame(minWidth: 20)
                .retroChip()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.editPlan)
        .accessibilityInputLabels([Copy.editPlan, Copy.planTheSet])
        .accessibilityShowsLargeContentViewer { Label(Copy.editPlan, systemImage: "list.bullet") }
    }

    private func chip(_ slot: SetPlan.Slot) -> some View {
        let state = Self.state(of: slot, in: plan, typed: typed)
        let pickable = Self.canPick(slot, typed: typed)
        return Button { pick(slot) } label: {
            PlanLabel(name: slot.name, symbol: services.symbol(for: slot.name), done: state == .done,
                      nameFrame: { report(slot.id, $0) })
                .retroChip(selected: state == .inField)
        }
        .buttonStyle(.plain)
        .disabled(!pickable)
        .accessibilityLabel(Copy.displayName(slot.name))
        .accessibilityValue(state == .done ? Copy.planDone : state == .inField ? Copy.planInField : "")
        .accessibilityHint(pickable ? Copy.putsInField : "")
    }
}

/// A planned name with its symbol, as a chip shows it and as it moves into
/// the name field.
struct PlanLabel: View {
    let name: String
    let symbol: String
    var done = false
    /// The name field's size rather than a chip's.
    var large = false
    /// Without it, just the name: what moves into the field, which has its own.
    var showsSymbol = true
    /// Told where the name is, in global space.
    var nameFrame: ((CGRect) -> Void)? = nil

    var body: some View {
        HStack(spacing: Space.xxs) {
            if showsSymbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
            }
            if done {
                // Done ones step aside to a symbol and a tick, so what's
                // still to do stays in sight; VoiceOver reads the name.
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
            } else {
                Text(Copy.displayName(name))
                    .font(.retro(large ? .body : .meta))
                    .foregroundStyle(Retro.ink)
                    .lineLimit(1)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { nameFrame?($0) }
            }
        }
    }
}
