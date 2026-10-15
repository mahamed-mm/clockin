import AVFoundation
import Foundation
import Testing
@testable import Clockin

/// The focus sounds' loops: all there, seamless, and never lining up soon.
struct FocusSoundTests {
    func file(_ name: String) throws -> AVAudioFile {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "caf"), "\(name).caf is missing")
        return try AVAudioFile(forReading: url)
    }

    @Test(arguments: FocusSound.allCases.filter { $0 != .off })
    func everyLayerIsBundled(_ sound: FocusSound) throws {
        #expect(!sound.layers.isEmpty)
        for layer in sound.layers {
            let audio = try file(layer)
            #expect(audio.fileFormat.channelCount == 1)
            #expect(audio.fileFormat.sampleRate == 32_000)
            #expect(audio.length > 0)
        }
    }

    @Test func offHasNothingToPlay() {
        #expect(FocusSound.off.layers.isEmpty)
    }

    /// Two layers only line up again after their lengths' least common
    /// multiple: at least 20 minutes, so a short session never hears a repeat.
    @Test(arguments: [FocusSound.rain, .fireplace])
    func layersTakeLongToLineUp(_ sound: FocusSound) throws {
        let seconds = try sound.layers.map { Int((Double(try file($0).length) / 32_000).rounded()) }
        #expect(seconds.count == 2)
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        #expect(gcd(seconds[0], seconds[1]) == 1)
        #expect(seconds[0] * seconds[1] >= 20 * 60)
    }

    /// The tick-tock's loop is exactly two seconds, so the beat never stumbles.
    @Test func theTickTockKeepsTime() throws {
        #expect(try file("focus-tick-tock").length == 64_000)
    }

    /// Loops run straight on: the step from the last sample to the first is
    /// no bigger than the loop's own biggest steps.
    @Test(arguments: FocusSound.allCases.flatMap(\.layers))
    func loopsAreSeamless(_ layer: String) throws {
        let audio = try file(layer)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        let steps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.sorted()
        let large = steps[Int(Double(steps.count) * 0.999)]
        #expect(abs(samples[0] - samples[samples.count - 1]) <= large)
    }
}
