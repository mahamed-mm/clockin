import SwiftUI

enum FocusLayout {
    /// The dial's side: the height left after everything around it, never
    /// wider than the column and never under `minimum`. When the minimum
    /// doesn't fit, the page scrolls.
    static func dialSide(viewportHeight: CGFloat, chrome: CGFloat, minimum: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(width, max(minimum, viewportHeight - chrome))
    }
}

extension View {
    /// Keeps `height` up to date with this view's laid-out height.
    func measuredHeight(_ height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.wrappedValue = $0 }
    }
}
