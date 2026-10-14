#if DEBUG
import SwiftUI

/// Tick's break under your thumb, in the gallery: pick a style and a
/// length, scrub through the break or let it run (sped up if you like),
/// and see Tick and the dial's words for that moment; or play any one
/// stretch on its own.
struct BreakSimulator: View {
    @State private var style = BreakStyle.stretch
    @State private var planned: TimeInterval = 300
    @State private var elapsed: TimeInterval = 0
    /// When the live break started, and how far in it was then, while one runs.
    @State private var live: (start: Date, elapsed: TimeInterval)?
    @State private var speed = 1.0
    /// One stretch playing on its own, how fast, and when it started.
    @State private var playing: (move: StretchMove, speed: Double, start: Date)?
    @State private var showsEnvelope = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Break").retroLabel()
            TimelineView(.animation(paused: live == nil && playing == nil)) { context in
                let date = moment(context.date)
                let activity = self.activity
                let frame = playing == nil ? BreakLoops(activity: activity).frame(at: date) : nil
                let pose = solo(at: context.date)
                VStack(spacing: Space.xs) {
                    TickFigure(rig: frame?.rig ?? (playing == nil ? TickRig(.onBreak) : TickRig.standing.applying(pose)),
                               face: frame?.face ?? (playing == nil ? TickFace(.onBreak) : TickFace.stretching.applying(pose)),
                               palette: .standard, progress: 1 - activity.remaining(at: date) / planned)
                        .scaleEffect(1 + 0.04 * (style == .breathe ? BreathCycle.standard.fullness(at: activity.styleElapsed(at: date)) : 0),
                                     anchor: UnitPoint(x: 0.5, y: 0.92))
                        .frame(width: 200, height: 200)
                        .overlay { if showsEnvelope { WorkoutEnvelope() } }
                    let guide = BreakGuide(activity: activity)
                    Text(guide.status(at: date) ?? "Running").retroLabel()
                    Text("\(TimeFormat.clock(activity.remaining(at: date))) left"
                         + (guide.step(at: date).map { " · \($0.index) of \($0.count)" } ?? ""))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
            .task(id: playing?.start) {
                guard let playing else { return }
                try? await Task.sleep(for: .seconds(playing.move.duration / playing.speed * Motion.speed))
                self.playing = nil
            }
            Picker("Style", selection: $style) {
                ForEach(BreakStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Length", selection: $planned) {
                ForEach([180.0, 300, 600, 900], id: \.self) { Text("\(Int($0 / 60)) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: planned) { elapsed = min(elapsed, planned) }
            HStack {
                Text("Into the break")
                Slider(value: $elapsed, in: 0...planned) { editing in
                    if !editing, live != nil { live = (.now, elapsed) }
                }
                Text(TimeFormat.clock(elapsed)).monospacedDigit()
            }
            Toggle("Live break", isOn: Binding(get: { live != nil }, set: { live = $0 ? (.now, elapsed) : nil }))
            Picker("Speed", selection: $speed) {
                ForEach([1.0, 10, 50], id: \.self) { Text("\(Int($0))×").tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: speed) { if let live { self.live = (.now, liveElapsed(.now, live)) } }
            Toggle("Show the envelope", isOn: $showsEnvelope)
            Text("Stretches").retroLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Space.xs)], spacing: Space.xs) {
                ForEach(StretchMove.allCases, id: \.self) { move in
                    Button(move.rawValue) { playing = (move, speed == 1 ? 1 : 4, .now) }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                }
            }
            .disabled(live != nil)
        }
        .font(.retro(.meta))
        .padding(Space.m)
        .background(Retro.paperDeep, in: .rect(cornerRadius: Radius.card))
    }

    /// The break as simulated: it began at the reference date, so the
    /// moment shown is `elapsed` seconds in.
    private var activity: TickBreak {
        TickBreak(planned: planned, endDate: Date(timeIntervalSinceReferenceDate: planned), pausedRemaining: nil,
                  style: style, from: 0)
    }

    /// The simulated clock: scrubbed, or running `speed` times as fast.
    private func moment(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: live.map { liveElapsed(date, $0) } ?? elapsed)
    }

    private func liveElapsed(_ date: Date, _ live: (start: Date, elapsed: TimeInterval)) -> TimeInterval {
        min(planned, live.elapsed + date.timeIntervalSince(live.start) * speed)
    }

    /// The stretch playing on its own (sped up, and in slow motion if that's on).
    private func solo(at date: Date) -> StretchPose {
        guard let playing else { return .rest }
        return playing.move.pose(at: date.timeIntervalSince(playing.start) / Motion.speed * playing.speed)
    }
}
#endif
