import SwiftUI

/// The symbols a name can have, to pick one: six to a row, four at the
/// largest text sizes. The current one is ringed in ink.
struct SymbolGrid: View {
    let selected: String
    let pick: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var cell: CGFloat = 44

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 44), spacing: Space.xs),
              count: dynamicTypeSize.isAccessibilitySize ? 4 : 6)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Space.xs) {
            ForEach(SymbolCatalog.ids, id: \.self) { id in
                Button { pick(id) } label: {
                    Image(systemName: id)
                        .font(.title3)
                        .foregroundStyle(Retro.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: min(cell, 72))
                        .background {
                            if id == selected {
                                Circle()
                                    .fill(Retro.ink.opacity(0.12))
                                    .strokeBorder(Retro.ink, lineWidth: 1.5)
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.symbolName(id))
                .accessibilityAddTraits(id == selected ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// The grid in a small popover, from the name field's symbol.
struct SymbolPicker: View {
    let name: String
    let selected: String
    let pick: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s) {
                Text(Copy.symbolFor(name))
                    .retroLabel()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                SymbolGrid(selected: selected, pick: pick)
            }
            .padding(Space.m)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 340)
        .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
        .presentationDetents([.large])
    }
}

#Preview {
    SymbolGrid(selected: "flask.fill") { _ in }
        .padding()
        .background(PaperBackground())
}
