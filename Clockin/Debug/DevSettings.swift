#if DEBUG
import SwiftUI

/// Development-only controls. Compiled out of Release builds.
struct DevMenu: View {
    @Bindable private var settings = DevSettings.shared
    @Environment(AppServices.self) private var services
    @State private var showsGallery = ProcessInfo.processInfo.arguments.contains("-MascotGallery")

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
                showsGallery = true
            } label: {
                Label("Tick gallery", systemImage: "face.smiling")
            }
            Menu {
                ForEach(0..<16, id: \.self) { back in
                    Button(back == 0 ? "This week" : "\(back) week\(back == 1 ? "" : "s") back") {
                        settings.postcardWeeksBack = back
                    }
                }
            } label: {
                Label("Postcard for a week", systemImage: "photo")
            }
            Button {
                UserDefaults.standard.set(true, forKey: ClockinTips.resetKey)
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
            Menu {
                ForEach(TimerSound.allCases, id: \.self) { sound in
                    Button(sound.rawValue) { SystemTimerSounds.debug.play(sound) }
                }
            } label: {
                Label("Sounds lab", systemImage: "speaker.wave.2")
            }
        } label: {
            Image(systemName: "ladybug")
        }
        .accessibilityLabel("Developer options")
        .sheet(isPresented: $showsGallery) { MascotGallery() }
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
    /// Opens History's postcard this many weeks back (0 for this week), via
    /// this menu or `-DemoPostcard N`. History takes it and clears it.
    var postcardWeeksBack: Int? = UserDefaults.standard.string(forKey: "DemoPostcard").flatMap { Int($0) }

    private init() {
        // Clear the flag older builds persisted.
        SharedStore.defaults.removeObject(forKey: "dev.shortTimers")
    }
}
#endif
