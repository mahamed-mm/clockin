#if DEBUG
import SwiftUI

/// Tick's character sheet, live: every state in light and dark at the
/// three detail levels, with the ring and motion under your thumb.
/// Development only, from the ladybug menu or `-MascotGallery`.
struct MascotGallery: View {
    @State private var state: TickPose? = nil
    @State private var usesSheetRing = true
    @State private var progress = 0.6
    @State private var reduceMotion = false
    @Bindable private var dev = DevSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    live
                    controls
                    ForEach(shown, id: \.self) { pose in
                        row(pose)
                    }
                }
                .padding(Space.l)
            }
            .background(Retro.paper)
            .navigationTitle("Tick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.tickReduceMotion, reduceMotion)
    }

    private var shown: [TickPose] { state.map { [$0] } ?? TickPose.allCases }

    /// The animated Tick, in the chosen state (ready when showing all).
    private var live: some View {
        let pose = state ?? .ready
        return VStack(spacing: Space.s) {
            TickView(pose: pose, progress: usesSheetRing ? .sheet : .fixed(progress))
                .frame(width: 200, height: 200)
            HStack {
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                Text(pose.rawValue).font(.retro(.label)).frame(minWidth: 110)
                Button("Next", systemImage: "chevron.right") { step(1) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.m)
        .background(Retro.paperDeep, in: .rect(cornerRadius: Radius.card))
    }

    private func step(_ by: Int) {
        let all = TickPose.allCases
        let index = all.firstIndex(of: state ?? .ready) ?? 0
        state = all[(index + by + all.count) % all.count]
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Picker("State", selection: $state) {
                Text("All states").tag(TickPose?.none)
                ForEach(TickPose.allCases, id: \.self) { Text($0.rawValue).tag(TickPose?.some($0)) }
            }
            Toggle("Ring from the sheet", isOn: $usesSheetRing)
            HStack {
                Text("Time left")
                Slider(value: $progress, in: 0...1)
                Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
            .disabled(usesSheetRing)
            Toggle("Reduce Motion", isOn: $reduceMotion)
            Toggle("Slow motion ×4", isOn: $dev.slowAnimations)
        }
        .font(.retro(.meta))
        .padding(Space.m)
        .background(Retro.paperDeep, in: .rect(cornerRadius: Radius.card))
    }

    private func row(_ pose: TickPose) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(pose.rawValue).retroLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    cell(pose, size: 180, scheme: .light)
                    cell(pose, size: 180, scheme: .dark)
                    cell(pose, size: 60, scheme: .light)
                    cell(pose, size: 60, scheme: .dark)
                    cell(pose, size: 20, scheme: .light)
                    cell(pose, size: 20, scheme: .dark)
                    // 16 px on a 2x screen, 24 px on 3x: the glyph's solid shapes.
                    cell(pose, size: 8, scheme: .light)
                }
            }
            .scrollClipDisabled()
        }
    }

    private func cell(_ pose: TickPose, size: Double, scheme: ColorScheme) -> some View {
        TickFigure(pose: pose, palette: .standard, progress: usesSheetRing ? nil : progress)
            .frame(width: size, height: size)
            .padding(size >= 60 ? Space.s : Space.xs)
            .background(Retro.paper, in: .rect(cornerRadius: max(4, size * 0.1)))
            .environment(\.colorScheme, scheme)
            .accessibilityLabel("\(pose.rawValue), \(Int(size)) points, \(scheme == .dark ? "dark" : "light")")
    }
}

#Preview {
    MascotGallery()
}
#endif
