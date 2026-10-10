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
        ("Break finished (success)", .breakFinished(live: true)),
        ("Focus complete (ding + sunburst)", .focusCompleted(live: true)),
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
                services.debugReplay(.focusCompleted(live: true))
            } label: {
                Label("Replay celebration", systemImage: "sparkles")
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
#endif
