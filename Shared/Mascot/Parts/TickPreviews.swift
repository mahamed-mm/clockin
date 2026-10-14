#if DEBUG
import SwiftUI

/// Tick in one state, light and dark, at the three detail levels.
private struct TickPreview: View {
    let pose: TickPose

    var body: some View {
        HStack(spacing: 16) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                VStack(spacing: 12) {
                    TickPartsFigure(pose: pose, palette: .standard).frame(width: 180, height: 180)
                    HStack(alignment: .bottom, spacing: 12) {
                        TickPartsFigure(pose: pose, palette: .standard).frame(width: 60, height: 60)
                        TickPartsFigure(pose: pose, palette: .standard).frame(width: 20, height: 20)
                        TickPartsFigure(pose: pose, palette: .standard).frame(width: 8, height: 8)
                    }
                }
                .padding(12)
                .background(Retro.paper, in: .rect(cornerRadius: 16))
                .environment(\.colorScheme, scheme)
            }
        }
        .padding()
    }
}

#Preview("ready") { TickPreview(pose: .ready) }
#Preview("working") { TickPreview(pose: .working) }
#Preview("waiting") { TickPreview(pose: .waiting) }
#Preview("done") { TickPreview(pose: .done) }
#Preview("onBreak") { TickPreview(pose: .onBreak) }
#Preview("ringing") { TickPreview(pose: .ringing) }
#Preview("hello") { TickPreview(pose: .hello) }
#Preview("interrupted") { TickPreview(pose: .interrupted) }
#Preview("streak") { TickPreview(pose: .streak) }
#Preview("sleeping") { TickPreview(pose: .sleeping) }
#endif
