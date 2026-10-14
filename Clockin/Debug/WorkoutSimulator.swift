#if DEBUG
import SwiftUI

/// Tick's workout under your thumb, in the gallery: pick a session length,
/// scrub the time left (or set the energy directly), and see the stance,
/// face and numbers for that moment; play any move or combo, or let a
/// live session run. The envelope shows where moves may reach without
/// covering the dial's knob or running off the screen.
struct WorkoutSimulator: View {
    @State private var planned: TimeInterval = 1500
    @State private var left: TimeInterval = 1500
    @State private var setsEnergy = false
    @State private var energyValue = 1.0
    @State private var showsEnvelope = false
    /// Moves playing one after another, at a tempo, and when they started.
    @State private var playing: (moves: [WorkoutMove], tempo: Double, start: Date)?
    /// When the live session ends, while one runs.
    @State private var liveEnd: Date?

    /// The moment shown: from the scrubber, or the time left that gives the chosen energy.
    private var energy: WorkoutEnergy {
        .at(planned: planned, remaining: setsEnergy ? Self.remaining(forEnergy: energyValue, planned: planned) : left)
    }

    var body: some View {
        let energy = energy
        let params = WorkoutParams(energy)
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Workout").retroLabel()
            Group {
                if let liveEnd {
                    // The real thing: TickView working through a session ending then.
                    TickView(pose: .working, progress: .fixed(1 - energy.elapsed / planned),
                             workout: TickWorkout(planned: planned, endDate: liveEnd, pausedRemaining: nil, seed: 1))
                } else {
                    TimelineView(.animation(paused: playing == nil)) { context in
                        let frame = frame(at: context.date, params: params)
                        TickFigure(rig: frame.rig, face: frame.face, palette: .standard, motion: frame.motion,
                                   progress: energy.elapsed >= planned ? 0 : 1 - energy.elapsed / planned)
                    }
                }
            }
            .frame(width: 200, height: 200)
            .overlay { if showsEnvelope { WorkoutEnvelope() } }
            .frame(maxWidth: .infinity)
            .task(id: playing?.start) {
                guard let playing else { return }
                let length = playing.moves.reduce(0) { $0 + $1.duration } / playing.tempo
                try? await Task.sleep(for: .seconds(length * Motion.speed))
                self.playing = nil
            }
            if liveEnd != nil {
                // The live session's moment, a second at a time.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = liveEnd.map { WorkoutEnergy.at(planned: planned, remaining: $0.timeIntervalSince(context.date)) } ?? energy
                    readout(now, WorkoutParams(now))
                }
            } else {
                readout(energy, params)
            }
            Toggle("Live session", isOn: Binding(get: { liveEnd != nil },
                                                 set: { liveEnd = $0 ? .now.addingTimeInterval(left) : nil }))
            Picker("Session", selection: $planned) {
                ForEach([900.0, 1500, 3000], id: \.self) { Text("\(Int($0 / 60)) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: planned) { left = min(left, planned) }
            HStack {
                Text("Time left")
                Slider(value: $left, in: 0...planned) { editing in
                    if !editing, liveEnd != nil { liveEnd = .now.addingTimeInterval(left) }
                }
                Text(TimeFormat.clock(left)).monospacedDigit()
            }
            .disabled(setsEnergy)
            Toggle("Set the energy instead", isOn: $setsEnergy)
            HStack {
                Text("Energy")
                Slider(value: $energyValue, in: 0.1...1)
                Text(energyValue, format: .number.precision(.fractionLength(2))).monospacedDigit()
            }
            .disabled(!setsEnergy)
            Toggle("Show the envelope", isOn: $showsEnvelope)
            Text("Moves").retroLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.xs)], spacing: Space.xs) {
                ForEach(WorkoutMove.allCases, id: \.self) { move in
                    Button(move.rawValue) { playing = ([move], params.tempo, .now) }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                }
            }
            .disabled(liveEnd != nil)
            Text("Combos").retroLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Space.xs)], spacing: Space.xs) {
                ForEach(WorkoutCombo.library + [.stretch, .finalPush(lasting: 10, tempo: 1.3)], id: \.name) { combo in
                    Button(combo.name) { playing = (combo.moves, params.tempo, .now) }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                }
            }
            .disabled(liveEnd != nil)
        }
        .font(.retro(.meta))
        .padding(Space.m)
        .background(Retro.paperDeep, in: .rect(cornerRadius: Radius.card))
    }

    /// The playing move's moment (at the tempo, and in slow motion if
    /// that's on), or the stance.
    private func frame(at date: Date, params: WorkoutParams) -> WorkoutFrame {
        guard let playing else { return WorkoutFrame(params: params) }
        var t = date.timeIntervalSince(playing.start) / Motion.speed * playing.tempo
        for move in playing.moves {
            if t < move.duration { return WorkoutFrame(params: params, move: move, at: t) }
            t -= move.duration
        }
        return WorkoutFrame(params: params)
    }

    private func readout(_ energy: WorkoutEnergy, _ params: WorkoutParams) -> some View {
        let phase = "\(energy.phase)".replacingOccurrences(of: "Push", with: " push")
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(phase), energy \(energy.energy, format: .number.precision(.fractionLength(2)))")
                .font(.retro(.label))
            Text("tempo \(params.tempo, format: .number.precision(.fractionLength(2))) · reach \(params.reach, format: .number.precision(.fractionLength(2))) · rest \(params.rest.lowerBound, format: .number.precision(.fractionLength(1)))–\(params.rest.upperBound, format: .number.precision(.fractionLength(1))) s")
            Text("bounce \(params.bounce, format: .number.precision(.fractionLength(2))) · breath \(params.breathPeriod.map { String(format: "%.1f s", $0) } ?? "spells") · sweat \(params.sweatRate, format: .number.precision(.fractionLength(2)))/s · hunch \(params.hunch, format: .number.precision(.fractionLength(1)))°")
        }
        .monospacedDigit()
    }

    /// The time left at which the energy is `target`: energy only falls as
    /// time passes, so halving finds it.
    static func remaining(forEnergy target: Double, planned: TimeInterval) -> TimeInterval {
        var low = 0.0, high = planned
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if WorkoutEnergy.at(planned: planned, remaining: mid).energy < target { low = mid } else { high = mid }
        }
        return high
    }
}

/// Where Tick's moves may reach, in its 100-unit square: clear of the dial's
/// knob on the left and the arc above, and of the screen edge on the right.
struct WorkoutEnvelope: View {
    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 100
            let allowed = CGRect(x: 4 * unit, y: 2 * unit, width: 96 * unit, height: 98 * unit)
            ZStack(alignment: .topLeading) {
                // The keep-out strips: the knob's side and the arc's.
                Rectangle().fill(.red.opacity(0.15)).frame(width: 4 * unit, height: 100 * unit)
                Rectangle().fill(.red.opacity(0.15)).frame(width: 100 * unit, height: 2 * unit)
                Rectangle()
                    .strokeBorder(.red.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: allowed.width, height: allowed.height)
                    .offset(x: allowed.minX, y: allowed.minY)
                Text("knob").font(.system(size: 9)).foregroundStyle(.red).rotationEffect(.degrees(-90))
                    .offset(x: -14, y: 50 * unit)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
