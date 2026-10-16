import SwiftUI
import Testing
@testable import Clockin

/// The paper's grain: faint, fainter on dark paper, gone with Increase Contrast.
struct PaperGrainTests {
    @Test func faintAndOffWithIncreaseContrast() {
        let light = PaperGrain.amount(scheme: .light, contrast: .standard)
        let dark = PaperGrain.amount(scheme: .dark, contrast: .standard)
        #expect(light > dark && dark > 0)
        #expect(light < 0.04)
        #expect(PaperGrain.amount(scheme: .light, contrast: .increased) == 0)
        #expect(PaperGrain.amount(scheme: .dark, contrast: .increased) == 0)
    }
}

/// Whether the grain survives `ImageRenderer`, for the week postcard.
@MainActor
struct PaperGrainRenderTests {
    /// How many different grey levels a flat paper square comes out with.
    static func distinctLevels(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Set(stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }).count
    }

    @Test func theShaderRendersOffScreen() throws {
        let renderer = ImageRenderer(content: Rectangle().fill(Color(white: 0.9)).frame(width: 60, height: 60)
            .paperGrain().environment(\.colorScheme, .light))
        renderer.scale = 3
        let image = try #require(renderer.cgImage)
        #expect(Self.distinctLevels(image) > 3)
    }
}
