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
                    if state == nil {
                        ForEach(Array((WorkoutSamples.stances + WorkoutSamples.faces).enumerated()), id: \.offset) { _, sample in
                            row(sample.name, rig: sample.rig, face: sample.face)
                        }
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
        row(pose.rawValue, rig: TickRig(pose), face: TickFace(pose), sheetProgress: pose.sheetProgress)
    }

    /// One pose at every size, in light and dark.
    private func row(_ name: String, rig: TickRig, face: TickFace, sheetProgress: Double = 0.6) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(name).retroLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    ForEach([180.0, 60, 20], id: \.self) { size in
                        cell(name, rig: rig, face: face, sheetProgress: sheetProgress, size: size, scheme: .light)
                        cell(name, rig: rig, face: face, sheetProgress: sheetProgress, size: size, scheme: .dark)
                    }
                    // 16 px on a 2x screen, 24 px on 3x: the glyph's solid shapes.
                    cell(name, rig: rig, face: face, sheetProgress: sheetProgress, size: 8, scheme: .light)
                }
            }
            .scrollClipDisabled()
        }
    }

    private func cell(_ name: String, rig: TickRig, face: TickFace, sheetProgress: Double, size: Double,
                      scheme: ColorScheme) -> some View {
        TickFigure(rig: rig, face: face, palette: .standard, progress: usesSheetRing ? sheetProgress : progress)
            .frame(width: size, height: size)
            .padding(size >= 60 ? Space.s : Space.xs)
            .background(Retro.paper, in: .rect(cornerRadius: max(4, size * 0.1)))
            .environment(\.colorScheme, scheme)
            .accessibilityLabel("\(name), \(Int(size)) points, \(scheme == .dark ? "dark" : "light")")
    }
}

#Preview {
    MascotGallery()
}
#endif
