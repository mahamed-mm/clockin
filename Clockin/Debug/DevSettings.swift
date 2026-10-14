#if DEBUG
import SwiftUI

/// Development-only controls. Compiled out of Release builds.
struct DevMenu: View {
    @Bindable private var settings = DevSettings.shared
    @Environment(AppServices.self) private var services

    private let hapticEvents: [(String, SessionEvent)] = [
        ("Start (medium impact)", .started),
        ("Pause / resume (selection)", .paused),
        ("Cancel (warning)", .cancelled),
        ("Break start (soft impact)", .breakStarted),
        ("Break skip (light impact)", .breakSkipped),
        ("Break finished (success)", .breakFinished(.live)),
        ("Focus complete (ding + sunburst)", .focusCompleted(.live)),
    ]

    var body: some View {
        Menu {
            Toggle(isOn: $settings.shortTimers) {
                Label("Short timers (10s / 5s)", systemImage: "hare")
            }
            Toggle(isOn: $settings.slowAnimations) {
                Label("Slow animations ×4", systemImage: "tortoise")
            }
            Button {
                services.debugReplay(.focusCompleted(.live))
            } label: {
                Label("Replay celebration", systemImage: "sparkles")
            }
            Button {
                Onboarding.reset()
            } label: {
                Label("Show first-launch hints again", systemImage: "hand.point.up.left")
            }
            Menu {
                ForEach(hapticEvents, id: \.0) { title, event in
                    Button(title) { services.debugReplay(event) }
                }
            } label: {
                Label("Haptics lab", systemImage: "waveform")
            }
        } label: {
            Image(systemName: "ladybug")
        }
        .accessibilityLabel("Developer options")
    }
}

/// Shown on the Focus screen while short timers are on, so they're never mistaken for real ones.
struct TestTimersBadge: View {
    var body: some View {
        if DevSettings.shared.shortTimers {
            Text("Test timers")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Retro.rust, in: .capsule)
        }
    }
}

/// Developer switches. In memory only, so a test setting can never stick
/// across launches.
@MainActor
@Observable
final class DevSettings {
    static let shared = DevSettings()

    /// Seconds instead of minutes (`TimerPlan.asTestTimers`), via this menu or the
    /// `-ShortTimers` launch argument.
    var shortTimers = ProcessInfo.processInfo.arguments.contains("-ShortTimers")
    /// Stretches every app animation ×4 so motion can be inspected frame by frame.
    var slowAnimations = ProcessInfo.processInfo.arguments.contains("-SlowAnimations")

    private init() {
        // Clear the flag older builds persisted.
        SharedStore.defaults.removeObject(forKey: "dev.shortTimers")
    }
}
#endif
