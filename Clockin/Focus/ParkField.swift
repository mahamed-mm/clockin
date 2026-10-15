import SwiftUI

/// One line above the keyboard for a stray thought: Return parks it and
/// closes; an empty line just closes.
struct ParkField: View {
    /// Parks the line; the field's frame, in global space, is where the slip leaves from.
    let park: (String, CGRect) -> Void
    let close: () -> Void
    @State private var text = ""
    @State private var frame: CGRect = .zero
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "note.text")
                .font(.body.weight(.semibold))
                .foregroundStyle(Retro.inkSoft)
                .accessibilityHidden(true)
            TextField(Copy.parkPlaceholder, text: $text)
                .font(.retro(.body))
                .foregroundStyle(Retro.ink)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit {
                    let line = text
                    text = ""
                    if ParkedThought.clean(line) != nil { park(line, frame) }
                    close()
                }
                .onChange(of: text) { _, line in
                    if line.count > ParkedThought.maxLength { text = String(line.prefix(ParkedThought.maxLength)) }
                }
                .accessibilityLabel(Copy.parkThought)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.xs)
        .frame(minHeight: 50)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.xs)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }

        .onAppear { focused = true }
        // The keyboard went away some other way: the field goes with it.
        .onChange(of: focused) { _, isFocused in if !isFocused { close() } }
    }
}

/// A parked thought on its way to Tick: a slip of paper along a short arc,
/// shrinking as it goes. Drawn only during the flight.
struct ParkedSlip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Retro.paper)
            .overlay {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<3) { line in
                        Capsule().fill(Retro.ink.opacity(0.35)).frame(width: line == 2 ? 14 : 22, height: 2)
                    }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Retro.ink.opacity(0.3), lineWidth: 1) }
            .frame(width: 34, height: 24)
            .shadow(color: Retro.ink.opacity(0.15), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// Moves along a curve from `from` to `to` as `progress` goes 0 to 1:
/// placed once at `from`, then moved by translation, so the flight lays
/// nothing out again.
struct SlipFlight: ViewModifier, Animatable {
    var from: CGPoint
    var to: CGPoint
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        // A quadratic curve that rises above the straight line, like a toss.
        let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 60)
        let x = (1 - t) * (1 - t) * from.x + 2 * (1 - t) * t * control.x + t * t * to.x
        let y = (1 - t) * (1 - t) * from.y + 2 * (1 - t) * t * control.y + t * t * to.y
        content
            .scaleEffect(1 - 0.45 * t)
            .rotationEffect(.degrees(-25 * t))
            .position(from)
            .offset(x: x - from.x, y: y - from.y)
            .opacity(t > 0.92 ? (1 - t) / 0.08 : 1)
    }
}
