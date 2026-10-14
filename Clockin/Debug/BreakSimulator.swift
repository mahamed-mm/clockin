#if DEBUG
import SwiftUI

/// Tick's break under your thumb, in the gallery: play any stretch, at
/// real speed or four times as fast, with the envelope if you like.
struct BreakSimulator: View {
    /// The stretch playing, how fast, and when it started.
    @State private var playing: (move: StretchMove, speed: Double, start: Date)?
    @State private var speed = 1.0
    @State private var showsEnvelope = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Break").retroLabel()
            TimelineView(.animation(paused: playing == nil)) { context in
                let pose = pose(at: context.date)
                TickFigure(rig: TickRig.standing.applying(pose), face: TickFace.stretching.applying(pose),
                           palette: .standard, progress: 0.5)
            }
            .frame(width: 200, height: 200)
            .overlay { if showsEnvelope { WorkoutEnvelope() } }
            .frame(maxWidth: .infinity)
            .task(id: playing?.start) {
                guard let playing else { return }
                try? await Task.sleep(for: .seconds(playing.move.duration / playing.speed * Motion.speed))
                self.playing = nil
            }
            Picker("Speed", selection: $speed) {
                ForEach([1.0, 4], id: \.self) { Text("\(Int($0))×").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show the envelope", isOn: $showsEnvelope)
            Text("Stretches").retroLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Space.xs)], spacing: Space.xs) {
                ForEach(StretchMove.allCases, id: \.self) { move in
                    Button(move.rawValue) { playing = (move, speed, .now) }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                }
            }
        }
        .font(.retro(.meta))
        .padding(Space.m)
        .background(Retro.paperDeep, in: .rect(cornerRadius: Radius.card))
    }

    /// The playing stretch's moment (sped up, and in slow motion if that's on), or the stance.
    private func pose(at date: Date) -> StretchPose {
        guard let playing else { return .rest }
        return playing.move.pose(at: date.timeIntervalSince(playing.start) / Motion.speed * playing.speed)
    }
}
#endif
