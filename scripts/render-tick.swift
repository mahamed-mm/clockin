// Renders Tick (Shared/Mascot/TickFigure.swift) on the Mac, for the app
// icon layers and for a contact sheet of every pose. Built and run by
// scripts/render-tick.sh; nothing here ships in the app.
import AppKit
import SwiftUI

@main
struct RenderTick {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard let mode = arguments.first, let out = arguments.dropFirst().first else {
            print("usage: render-tick sheet|shapes <file.png> | icon <directory>")
            exit(2)
        }
        switch mode {
        case "sheet": try write(ContactSheet(), scale: 2, to: URL(fileURLWithPath: out))
        case "shapes": try write(Silhouettes(), scale: 2, to: URL(fileURLWithPath: out))
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
        let light = TickPalette.fixed(dark: false)
        let dark = TickPalette.fixed(dark: true)
        let paper = Color(red: 0.953, green: 0.914, blue: 0.839)
        let night = Color(red: 0.110, green: 0.094, blue: 0.078)
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
                    TickFigure(pose: pose, palette: light).frame(width: 180, height: 180)
                        .padding(8).background(paper, in: .rect(cornerRadius: 16))
                    TickFigure(pose: pose, palette: dark).frame(width: 180, height: 180)
                        .padding(8).background(night, in: .rect(cornerRadius: 16))
                    TickFigure(pose: pose, palette: light).frame(width: 60, height: 60)
                        .padding(6).background(paper, in: .rect(cornerRadius: 10))
                    TickFigure(pose: pose, palette: light).frame(width: 20, height: 20)
                        .padding(4).background(paper, in: .rect(cornerRadius: 6))
                    // True 16 px (8 pt on this 2x sheet); the glyph fills ~90% of it.
                    TickFigure(pose: pose, palette: light).frame(width: 8, height: 8)
                        .background(paper)
                }
            }
        }
        .padding(24)
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
                    TickFigure(pose: pose, palette: .fixed(dark: false))
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
        TickFigure(pose: pose, palette: .icon, detail: .simplified)
            .frame(width: 860, height: 860)
            .offset(y: 30)
            .frame(width: 1024, height: 1024)
    }
}
