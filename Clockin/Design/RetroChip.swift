import SwiftUI

extension View {
    /// The one small capsule chip: recent names and the length choices. A
    /// selected chip fills with the tint; the rest are plain glass.
    func retroChip(selected: Bool = false, tint: Color = Retro.orange) -> some View {
        padding(.horizontal, Space.m)
            .frame(minHeight: 36)
            .contentShape(.capsule)
            .glassEffect(selected ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
    }
}
