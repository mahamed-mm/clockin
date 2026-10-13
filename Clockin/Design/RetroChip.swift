import SwiftUI

extension View {
    /// The one small capsule chip: recent names and the length choices. A
    /// selected chip takes a wash of the tint, light enough that ink text
    /// stays readable on it in both appearances; the rest are plain glass.
    func retroChip(selected: Bool = false, tint: Color = Retro.orange) -> some View {
        padding(.horizontal, Space.m)
            .frame(minHeight: 36)
            .contentShape(.capsule)
            .glassEffect(selected ? .regular.tint(tint.opacity(0.4)).interactive() : .regular.interactive(),
                         in: .capsule)
    }
}
