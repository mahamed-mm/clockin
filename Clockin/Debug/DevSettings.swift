#if DEBUG
import AlarmKit
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
                Task { await DevAlarm.ringInOneMinute() }
            } label: {
                Label("Ring in 1 minute (AlarmKit)", systemImage: "alarm")
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

/// The AlarmKit spike: can a Personal Team build ring through Silent and Focus?
enum DevAlarm {
    struct Metadata: AlarmMetadata {}

    static func ringInOneMinute() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            Log.notifications.info("AlarmKit authorization: \(String(describing: state), privacy: .public)")
            guard state == .authorized else { return }
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: "Test alarm from Clockin")
            } else {
                alert = AlarmPresentation.Alert(title: "Test alarm from Clockin",
                                                stopButton: AlarmButton(text: "Stop", textColor: .white,
                                                                        systemImageName: "stop.circle"))
            }
            let attributes = AlarmAttributes<Metadata>(presentation: AlarmPresentation(alert: alert),
                                                       tintColor: Retro.orange)
            let alarm = try await AlarmManager.shared.schedule(
                id: UUID(),
                configuration: .alarm(schedule: .fixed(.now.addingTimeInterval(60)), attributes: attributes))
            Log.notifications.info("AlarmKit scheduled: \(String(describing: alarm.state), privacy: .public)")
        } catch {
            Log.notifications.error("AlarmKit failed: \(error, privacy: .public)")
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
