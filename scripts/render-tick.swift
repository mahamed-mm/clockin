// Renders Tick (Shared/Mascot/TickFigure.swift) on the Mac, for the app
// icon layers and for a contact sheet of every pose. Built and run by
// scripts/render-tick.sh; nothing here ships in the app.
import AppKit
import SwiftUI

/// The app's asset catalog, compiled for the Mac by render-tick.sh: the
/// same Tick colour sets the app uses.
@MainActor let assets: Bundle = {
    guard let path = ProcessInfo.processInfo.environment["TICK_ASSETS"], let bundle = Bundle(path: path) else {
        fatalError("Run through scripts/render-tick.sh, which compiles the asset catalog.")
    }
    return bundle
}()

@main
struct RenderTick {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard let mode = arguments.first, let out = arguments.dropFirst().first else {
            print("usage: render-tick sheet|shapes|workout|hero <file.png> | icon <directory>")
            exit(2)
        }
        switch mode {
        case "sheet": try write(ContactSheet(), scale: 2, to: URL(fileURLWithPath: out))
        case "shapes": try write(Silhouettes(), scale: 2, to: URL(fileURLWithPath: out))
        case "workout": try write(WorkoutSheet(), scale: 2, to: URL(fileURLWithPath: out))
        case "moves": try write(MoveSheet(), scale: 2, to: URL(fileURLWithPath: out))
        case "hero":
            // The README's banner: the name in Fraunces, Tick working, resting, done.
            for font in ["Display", "Title", "Text"] {
                let url = URL(fileURLWithPath: "Shared/Fonts/FrauncesClockin-\(font).ttf")
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            try write(Hero(), scale: 2, to: URL(fileURLWithPath: out))
        case "icon":
            // The icon's Tick layers: 1024 px, transparent, for Icon Composer bundles.
            let directory = URL(fileURLWithPath: out)
            for (pose, name) in [(TickPose.working, "tick-working"), (.onBreak, "tick-break")] {
                try write(IconLayer(pose: pose), scale: 1, to: directory.appendingPathComponent("\(name).png"))
            }
        default:
            print("unknown mode \(mode)")
            exit(2)
        }
    }

    @MainActor
    static func write(_ view: some View, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        print("wrote \(url.path)")
    }
}

/// Every pose at hero, in-app and Dynamic Island sizes, on the light and
/// dark pages, plus the 16 px silhouette test.
struct ContactSheet: View {
    var body: some View {
        let palette = TickPalette.assets(in: assets)
        let paper = Color("Paper", bundle: assets)
        Grid(horizontalSpacing: 18, verticalSpacing: 14) {
            GridRow {
                Text("pose").bold()
                Text("180 pt, light").bold()
                Text("180 pt, dark").bold()
                Text("60 pt").bold()
                Text("20 pt").bold()
                Text("16 px shape").bold()
            }
            .font(.system(size: 13))
            ForEach(TickPose.allCases, id: \.self) { pose in
                GridRow {
                    Text(pose.rawValue).font(.system(size: 15, weight: .semibold))
                    TickFigure(pose: pose, palette: palette).frame(width: 180, height: 180)
                        .padding(8).background(paper, in: .rect(cornerRadius: 16))
                    TickFigure(pose: pose, palette: palette).frame(width: 180, height: 180)
                        .padding(8).background(paper, in: .rect(cornerRadius: 16))
                        .environment(\.colorScheme, .dark)
                    TickFigure(pose: pose, palette: palette).frame(width: 60, height: 60)
                        .padding(6).background(paper, in: .rect(cornerRadius: 10))
                    TickFigure(pose: pose, palette: palette).frame(width: 20, height: 20)
                        .padding(4).background(paper, in: .rect(cornerRadius: 6))
                    // True 16 px (8 pt on this 2x sheet); the glyph fills ~90% of it.
                    TickFigure(pose: pose, palette: palette).frame(width: 8, height: 8)
                        .background(paper)
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.97))
        .foregroundStyle(Color(white: 0.15))
    }
}

/// The workout's stances at the same sizes, for tuning them.
struct WorkoutSheet: View {
    var body: some View {
        let palette = TickPalette.assets(in: assets)
        let paper = Color("Paper", bundle: assets)
        Grid(horizontalSpacing: 18, verticalSpacing: 14) {
            ForEach(Array((WorkoutSamples.stances + WorkoutSamples.faces).enumerated()), id: \.offset) { _, sample in
                let face = sample.face
                GridRow {
                    Text(sample.name).font(.system(size: 15, weight: .semibold))
                    TickFigure(rig: sample.rig, face: face, palette: palette, progress: 0.6).frame(width: 180, height: 180)
                        .padding(8).background(paper, in: .rect(cornerRadius: 16))
                    TickFigure(rig: sample.rig, face: face, palette: palette, progress: 0.6).frame(width: 180, height: 180)
                        .padding(8).background(paper, in: .rect(cornerRadius: 16))
                        .environment(\.colorScheme, .dark)
                    TickFigure(rig: sample.rig, face: face, palette: palette, progress: 0.6).frame(width: 106, height: 106)
                        .padding(6).background(paper, in: .rect(cornerRadius: 12))
                    TickFigure(rig: sample.rig, face: face, palette: palette, progress: 0.6).frame(width: 60, height: 60)
                        .padding(6).background(paper, in: .rect(cornerRadius: 10))
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.97))
        .foregroundStyle(Color(white: 0.15))
    }
}

/// Every move as a strip of frames, on the strong stance (worn-out moves
/// on the exhausted one), with Tick's square outlined.
struct MoveSheet: View {
    var body: some View {
        let palette = TickPalette.assets(in: assets)
        let paper = Color("Paper", bundle: assets)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(WorkoutMove.allCases, id: \.self) { move in
                let params = WorkoutSamples.params(left: [.wipe, .weakJab].contains(move) ? 30 : 900)
                let frames = 12
                HStack(spacing: 6) {
                    Text(move.rawValue).font(.system(size: 13, weight: .semibold)).frame(width: 90, alignment: .leading)
                    ForEach(0..<frames, id: \.self) { i in
                        let t = move.duration * Double(i) / Double(frames - 1)
                        let frame = WorkoutFrame(params: params, move: move, at: t)
                        TickFigure(rig: frame.rig, face: frame.face, palette: palette, motion: frame.motion, progress: 0.6)
                            .frame(width: 96, height: 96)
                            .border(Color.red.opacity(0.25), width: 0.5)
                            .background(paper)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.97))
        .foregroundStyle(Color(white: 0.15))
    }
}

/// Every pose filled solid black at 60 pt: each should be tellable apart.
struct Silhouettes: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(TickPose.allCases, id: \.self) { pose in
                VStack(spacing: 6) {
                    TickFigure(pose: pose, palette: .assets(in: assets))
                        .frame(width: 60, height: 60)
                        .colorMultiply(.black)
                    Text(pose.rawValue).font(.system(size: 11))
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .foregroundStyle(Color(white: 0.2))
    }
}

/// One icon layer: Tick, large and centred, on transparency. The limbs are
/// deep terracotta so the same picture reads on the light and dark icon.
struct IconLayer: View {
    let pose: TickPose

    var body: some View {
        TickFigure(pose: pose, palette: .icon(in: assets), detail: .simplified)
            .frame(width: 860, height: 860)
            .offset(y: 30)
            .frame(width: 1024, height: 1024)
    }
}

/// The README's banner, 1600 x 933: the name, the line, the set of four,
/// and Tick at work, on a break and done.
struct Hero: View {
    let ink = Color("Ink", bundle: assets)
    let soft = Color("InkSoft", bundle: assets)
    let stripes = ["Rust", "BurntOrange", "Mustard"].map { Color($0, bundle: assets) }

    var body: some View {
        let palette = TickPalette.assets(in: assets)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Clockin")
                    .font(.custom("FrauncesClockin-Display", size: 150))
                    .foregroundStyle(ink)
                Text("One thing at a time.")
                    .font(.custom("FrauncesClockin-Title", size: 46))
                    .foregroundStyle(soft)
                Text("A retro focus timer for iPhone")
                    .font(.custom("FrauncesClockin-Text", size: 32))
                    .foregroundStyle(soft)
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(stripes[i]).frame(width: 60, height: 16)
                    }
                    Capsule().strokeBorder(Color("Avocado", bundle: assets), lineWidth: 3)
                        .frame(width: 60, height: 16)
                }
                .padding(.top, 28)
            }
            .padding(.leading, 104)
            Spacer(minLength: 0)
            ZStack {
                TickFigure(pose: .working, palette: palette, detail: .handmade)
                    .frame(width: 330, height: 330)
                    .offset(x: -190, y: 90)
                TickFigure(pose: .onBreak, palette: palette, detail: .handmade)
                    .frame(width: 300, height: 300)
                    .offset(x: 170, y: 110)
                TickFigure(pose: .done, palette: palette, detail: .handmade)
                    .frame(width: 400, height: 400)
                    .offset(x: -10, y: -110)
            }
            .frame(width: 760)
            .padding(.trailing, 40)
        }
        .frame(width: 1600, height: 933)
        .background(Color(red: 0.91, green: 0.83, blue: 0.68))
    }
}
