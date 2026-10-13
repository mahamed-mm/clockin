import SwiftUI

/// The one recipe for a small modal: a close button, a centred header (a
/// symbol, a tinted overline, the title), grouped rows, then the actions.
/// Presented with `fittedSheet()`, iOS floats it inset on glass at the
/// height of its content.
struct CardSheet<Title: View, Rows: View, Actions: View>: View {
    var symbol: String?
    var tint: Color = Retro.orangeText
    var overline: String
    @ViewBuilder var title: Title
    @ViewBuilder var rows: Rows
    @ViewBuilder var actions: Actions
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title) private var badge: CGFloat = 52

    var body: some View {
        VStack(spacing: Space.l) {
            ZStack(alignment: .topLeading) {
                header
                CloseButton { dismiss() }
            }
            VStack(spacing: 0) {
                Group(subviews: rows) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(Retro.ink.opacity(0.1))
                                .frame(height: 1)
                                .padding(.leading, Space.m)
                                .accessibilityHidden(true)
                        }
                        row
                    }
                }
            }
            .background(Retro.paperDeep.opacity(0.6), in: .rect(cornerRadius: Radius.card))
            VStack(spacing: Space.xxs) {
                actions
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }

    private var header: some View {
        VStack(spacing: Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: badge, height: badge)
                    .background(tint.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
                    .padding(.bottom, Space.xxs)
            }
            Text(overline)
                .font(.retro(.label))
                .textCase(.uppercase)
                .tracking(2.2)
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
            title
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // Clear of the close button on both sides, so long titles stay centred.
        .padding(.horizontal, 44)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .contain)
    }
}

/// One line in a card: what it is on the left, the value on the right.
/// Stacks when large text wouldn't fit both.
struct CardRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xxs))
            : AnyLayout(HStackLayout(spacing: Space.s))
        layout {
            Text(label)
                .foregroundStyle(Retro.ink)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value)
                .foregroundStyle(Retro.inkSoft)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .font(.retro(.body))
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A quiet text action under a card's rows; destructive ones are rust.
struct CardAction: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .font(.retro(.body).weight(.semibold))
        .foregroundStyle(role == .destructive ? Retro.rustText : Retro.orangeText)
        .buttonStyle(.borderless)
    }
}

/// The round glass X that closes every modal, top left.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Retro.ink)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Close"))
        .accessibilityShowsLargeContentViewer { Label(String(localized: "Close"), systemImage: "xmark") }
    }
}

extension View {
    /// Presents this as a sheet exactly as tall as its content, which iOS
    /// floats inset on glass. Scrolls if it won't fit.
    func fittedSheet() -> some View {
        modifier(FittedSheet())
    }
}

private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
    }
}
