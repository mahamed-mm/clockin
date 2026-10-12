import SwiftUI

/// The few things worth choosing, opened from the gear on the Focus screen.
struct SettingsSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingErase = false

    var body: some View {
        NavigationStack {
            List {
                timer
                longBreak
                alerts
                data
                about
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Timer

    private var timer: some View {
        Section {
            ForEach(Preset.allCases) { preset in
                let selected = services.settings.preset == preset
                Button {
                    services.settings.preset = preset
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.retro(.headline))
                                .foregroundStyle(Retro.ink)
                            Text(preset.detail)
                                .font(.retro(.meta))
                                .foregroundStyle(Retro.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Retro.orange)
                            .opacity(selected ? 1 : 0)
                    }
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .listRowBackground(rowBackground)
            }
        } header: {
            Text("Timer").retroLabel()
        } footer: {
            Text("Applies from the next session.")
        }
    }

    // MARK: Long break

    private var longBreak: some View {
        @Bindable var services = services
        return Section {
            Toggle(isOn: $services.settings.longBreak) {
                Text("Long break after four")
            }
            .tint(Retro.orange)
            .listRowBackground(rowBackground)
        } footer: {
            Text("Every fourth full session of the day earns a \(TimeFormat.duration(TimerPlan.longBreakLength)) break.")
        }
    }

    // MARK: Alerts

    private var alerts: some View {
        Section {
            LabeledContent("Alerts & Live Activities") {
                Text(alertSummary)
            }
            .listRowBackground(rowBackground)
            if let settingsURL {
                Button("Open Settings") { openURL(settingsURL) }
                    .foregroundStyle(Retro.orange)
                    .listRowBackground(rowBackground)
            }
        } header: {
            Text("When time's up").retroLabel()
        }
    }

    private var alertSummary: String {
        switch services.alertStatus {
        case .ready: String(localized: "On")
        case .notAsked: String(localized: "Asked on your first start")
        case .notificationsOff: String(localized: "Alerts off")
        case .liveActivitiesOff: String(localized: "Live Activities off")
        case .unknown: ""
        }
    }

    private var settingsURL: URL? {
        switch services.alertStatus {
        case .notificationsOff: URL(string: UIApplication.openNotificationSettingsURLString)
        case .liveActivitiesOff: URL(string: UIApplication.openSettingsURLString)
        case .unknown, .notAsked, .ready: nil
        }
    }

    // MARK: Your data

    private var data: some View {
        Section {
            Button("Erase all history…", role: .destructive) { confirmingErase = true }
                .disabled(services.history == nil)
                .listRowBackground(rowBackground)
        } header: {
            Text("Your data").retroLabel()
        }
        .confirmationDialog("Erase all history?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase All", role: .destructive) { services.eraseHistory() }
        } message: {
            Text("Every saved session is deleted from this iPhone. This can't be undone.")
        }
    }

    // MARK: About

    private var about: some View {
        Section {
            LabeledContent("Version", value: version)
                .listRowBackground(rowBackground)
        } header: {
            Text("About").retroLabel()
        } footer: {
            Text("Everything stays on this iPhone.")
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var rowBackground: Color { Retro.paperDeep.opacity(0.6) }
}

#if DEBUG
#Preview {
    SettingsSheet()
        .environment(AppServices.preview)
}
#endif
