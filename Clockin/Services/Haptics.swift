import CoreHaptics
import UIKit

/// The "kitchen-timer ding" played when a focus session completes:
/// three rising taps followed by a soft swell.
@MainActor
final class CompletionHaptics {
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play() {
        guard supportsHaptics else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        do {
            let engine = try self.engine ?? makeEngine()
            try engine.start()
            let player = try engine.makePlayer(with: try Self.pattern())
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        self.engine = engine
        return engine
    }

    static func pattern() throws -> CHHapticPattern {
        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        let swell = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
        ], relativeTime: 0.42, duration: 0.6)
        let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.2),
            .init(relativeTime: 0.18, value: 1),
            .init(relativeTime: 0.6, value: 0),
        ], relativeTime: 0.42)
        return try CHHapticPattern(
            events: [tap(0, 0.4, 0.5), tap(0.14, 0.7, 0.6), tap(0.28, 1, 0.75), swell],
            parameterCurves: [fade]
        )
    }
}
