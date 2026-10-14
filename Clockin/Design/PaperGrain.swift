import SwiftUI

/// A faint static grain on the app's paper, like the real thing: a few
/// percent of brightness either way (`PaperGrain.metal`), a little less on
/// the dark paper, none with Increase Contrast. The shader has no time
/// input, so it's drawn with the page and never redraws on its own. For
/// the background only, never text or cards; the widget and Live Activity
/// keep plain paper.
struct PaperGrain: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// How far the grain moves the brightness, 0 for none.
    static func amount(scheme: ColorScheme, contrast: ColorSchemeContrast) -> Float {
        guard contrast != .increased else { return 0 }
        return scheme == .dark ? 0.022 : 0.03
    }

    func body(content: Content) -> some View {
        let amount = Self.amount(scheme: scheme, contrast: contrast)
        if amount > 0 {
            content.colorEffect(ShaderLibrary.paperGrain(.float(amount)))
        } else {
            content
        }
    }
}

extension View {
    /// The app's paper grain (see `PaperGrain`).
    func paperGrain() -> some View {
        modifier(PaperGrain())
    }
}
