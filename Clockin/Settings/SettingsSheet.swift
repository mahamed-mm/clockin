import SwiftUI
import UniformTypeIdentifiers

/// The few things worth choosing, opened from the gear on the Focus screen.
struct SettingsSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingErase = false
    @State private var exportFile: ExportFile?
    @State private var importing = false
    @State private var importReview: ImportReview?

    var body: some View {
        NavigationStack {
            List {
                timer
                appearance
                mascot
                longBreak
                sounds
                bedside
                alerts
                weekSummaries
                data
                about
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, Space.gutter, for: .scrollContent)
            .background(PaperBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Changes apply as they're made, so there's nothing to confirm:
                // the same X as every other modal.
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                        .tint(Retro.ink)
                }
            }
        }
    }

    // MARK: Timer

    private var timer: some View {
        Section {
            ForEach(Preset.allCases) { preset in
                let selected = services.settings.length == .preset(preset)
                Button {
                    services.settings.length = .preset(preset)
                } label: {
                    lengthRow(.preset(preset), selected: selected)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .listRowBackground(rowBackground)
            }
            // A length dragged on the dial; choosing a preset replaces it.
            if case .custom = services.settings.length {
                lengthRow(services.settings.length, selected: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isSelected)
                    .listRowBackground(rowBackground)
            }
        } header: {
            Text("Timer").retroLabel()
        } footer: {
            Text("Applies from the next session. Or drag the dial on the Focus screen.")
        }
    }

    private func lengthRow(_ length: SessionLength, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(length.title)
                    .retroFont(.headline)
                    .foregroundStyle(Retro.ink)
                Text(length.detail)
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
            }
            Spacer()
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(Retro.orangeText)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(.rect)
    }

    // MARK: Appearance

    private var appearance: some View {
        @Bindable var services = services
        return Section {
            Picker("Appearance", selection: $services.settings.appearance) {
                ForEach(Appearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(rowBackground)
            AppIconPicker(selection: services.appIconChoice) { choice in
                Task { await services.chooseAppIcon(choice) }
            }
            .listRowBackground(rowBackground)
        } header: {
            Text("Appearance").retroLabel()
        } footer: {
            Text("The widget and Lock Screen follow your iPhone's setting. The app icon is Tick at work or on a break.")
        }
    }

    // MARK: Tick

    private var mascot: some View {
        @Bindable var services = services
        return Section {
            Picker("Mascot during focus", selection: $services.settings.mascotDuringFocus) {
                ForEach(MascotFocusStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(rowBackground)
        } header: {
            Text("Mascot during focus").retroLabel()
        } footer: {
            Text("Tick boxes through a session in short bursts and tires as the time runs out. Calm keeps it in guard. Reduce Motion and Low Power Mode keep it calm and still.")
        }
    }

    // MARK: Break

    private var longBreak: some View {
        @Bindable var services = services
        return Section {
            Picker("During breaks", selection: $services.settings.duringBreaks) {
                ForEach(BreakStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(rowBackground)
            Toggle(isOn: $services.settings.longBreak) {
                RowLabel("Long break after four", symbol: "cup.and.saucer")
            }
            .tint(Retro.orange)
            .listRowBackground(rowBackground)
        } header: {
            Text("Break").retroLabel()
        } footer: {
            Text("Rest with Tick, stretch along with it, or breathe in time with the dial. You can change it on the break screen for that break. Every fourth full session of the day earns a \(TimeFormat.duration(TimerPlan.longBreakLength)) break.")
        }
    }

    // MARK: Sounds

    private var sounds: some View {
        @Bindable var services = services
        return Section {
            Toggle(isOn: $services.settings.timerSounds) {
                RowLabel("Timer sounds", symbol: "speaker.wave.2")
            }
            .tint(Retro.orange)
            .listRowBackground(rowBackground)
        } header: {
            Text("Sounds").retroLabel()
        } footer: {
            Text("Silent mode mutes them.")
        }
    }

    // MARK: Week summaries

    /// Only on phones whose Apple Intelligence can write them.
    @ViewBuilder
    private var weekSummaries: some View {
        @Bindable var services = services
        if services.weekWriter.isAvailable {
            Section {
                Toggle(isOn: $services.settings.weekSummaries) {
                    RowLabel("Week summaries", symbol: "apple.intelligence")
                }
                .tint(Retro.orange)
                .listRowBackground(rowBackground)
            } footer: {
                Text("Apple Intelligence writes History's line about your week on this iPhone, from session times only. Nothing leaves the phone.")
            }
        }
    }

    // MARK: Bedside clock

    private var bedside: some View {
        @Bindable var services = services
        return Section {
            Toggle(isOn: $services.settings.bedsideWhenSideways) {
                RowLabel("Turn sideways for the bedside clock", symbol: "rotate.right")
            }
            .tint(Retro.orange)
            .listRowBackground(rowBackground)
            Button {
                services.bedside.enter()
                dismiss()
            } label: {
                RowLabel("Show bedside clock", symbol: "moon.stars")
            }
            .disabled(services.engine.active == nil)
            .listRowBackground(rowBackground)
        } header: {
            Text("Bedside clock").retroLabel()
        } footer: {
            Text("A dimmed landscape clock for the nightstand. Show it during a session, even with orientation lock on.")
        }
    }

    // MARK: Alerts

    private var alerts: some View {
        Section {
            Toggle(isOn: Binding(get: { services.settings.ringAtEnd },
                                 set: { on in Task { await services.setRingAtEnd(on) } })) {
                RowLabel("Ring when time's up", symbol: "alarm")
            }
            .tint(Retro.orange)
            .listRowBackground(rowBackground)
            LabeledContent {
                Text(alertSummary)
            } label: {
                RowLabel("Alerts & Live Activities", symbol: "bell")
            }
            .listRowBackground(rowBackground)
            if let settingsURL {
                Button { openURL(settingsURL) } label: {
                    RowLabel("Open Settings", symbol: "arrow.up.forward.app")
                }
                    .listRowBackground(rowBackground)
            }
        } header: {
            Text("When time's up").retroLabel()
        } footer: {
            if services.settings.ringAtEnd {
                Text("Rings like an alarm, even on silent and in a Focus, until you stop it.")
            } else {
                Text("Off, a notification plays the chime, and Silent mode or a Focus can hush it.")
            }
        }
    }

    private var alertSummary: String {
        switch services.alertStatus {
        case .ready: String(localized: "On")
        case .notAsked: String(localized: "Asked on your first start")
        case .notificationsOff: String(localized: "Alerts off")
        case .liveActivitiesOff: String(localized: "Live Activities off")
        case .alarmsOff: String(localized: "Alarms off")
        case .unknown: ""
        }
    }

    private var settingsURL: URL? {
        switch services.alertStatus {
        case .notificationsOff: URL(string: UIApplication.openNotificationSettingsURLString)
        case .liveActivitiesOff, .alarmsOff: URL(string: UIApplication.openSettingsURLString)
        case .unknown, .notAsked, .ready: nil
        }
    }

    // MARK: Your data

    private var data: some View {
        Section {
            Toggle(isOn: Binding(get: { services.settings.saveToHealth },
                                 set: { on in Task { await services.setSaveToHealth(on) } })) {
                RowLabel("Save to Apple Health", symbol: "heart.text.square")
            }
            .tint(Retro.orange)
            .listRowBackground(rowBackground)
            Group {
                Button { export(.commaSeparatedText) } label: {
                    RowLabel("Export as CSV", symbol: "tablecells")
                }
                Button { export(.json) } label: {
                    RowLabel("Back up History", symbol: "externaldrive")
                }
                Button { importing = true } label: {
                    RowLabel("Restore from a backup…", symbol: "arrow.counterclockwise")
                }
                Button(role: .destructive) { confirmingErase = true } label: {
                    RowLabel("Erase all history…", symbol: "trash", tint: Retro.rustText)
                }
                .foregroundStyle(Retro.rustText)
            }
            .disabled(services.history == nil)
            .listRowBackground(rowBackground)
        } header: {
            Text("Your data").retroLabel()
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                if services.healthPermission == .denied {
                    Text("Health access is off for Clockin. Turn it on in the Health app: your profile › Apps › Clockin.")
                } else {
                    Text("Finished focus sessions appear in Health as Mindful Minutes. Clockin doesn't read anything from Health.")
                }
                Text("CSV opens in Numbers or Excel. A backup restores here, keeping the sessions you already have.")
            }
        }
        .confirmationDialog("Erase all history?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase All", role: .destructive) { services.eraseHistory() }
        } message: {
            Text("Every saved session is deleted from this iPhone. This can't be undone.")
        }
        .fileExporter(isPresented: isExporting, document: exportFile,
                      contentType: exportFile?.contentType ?? .json,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result {
                Log.store.error("Export failed: \(error, privacy: .public)")
            }
            exportFile = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            readBackup(result)
        }
        .alert(importTitle, isPresented: isReviewingImport, presenting: importReview) { review in
            switch review {
            case .ready(let plan) where !plan.isEmpty:
                Button("Restore") { restore(plan) }
                Button("Cancel", role: .cancel) {}
            default:
                Button("OK", role: .cancel) {}
            }
        } message: { review in
            Text(importMessage(review))
        }
    }

    // MARK: Export and restore

    private enum ImportReview {
        case ready(HistoryExport.ImportPlan)
        case failed(String)
    }

    private var isExporting: Binding<Bool> {
        Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } })
    }

    private var isReviewingImport: Binding<Bool> {
        Binding(get: { importReview != nil }, set: { if !$0 { importReview = nil } })
    }

    private var exportName: String {
        HistoryExport.fileName(exportFile?.contentType == .json ? "backup" : "sessions", on: .now)
    }

    private func export(_ type: UTType) {
        guard let history = services.history else { return }
        do {
            let sessions = try history.allSessions()
            let data = type == .json
                ? try HistoryExport.backup(sessions, exportedAt: .now)
                : Data(HistoryExport.csv(sessions).utf8)
            exportFile = ExportFile(data: data, contentType: type)
        } catch {
            Log.store.error("Couldn't prepare an export: \(error, privacy: .public)")
        }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // Files from the picker live outside the sandbox until claimed.
            let claimed = url.startAccessingSecurityScopedResource()
            defer { if claimed { url.stopAccessingSecurityScopedResource() } }
            importReview = .ready(try services.planImport(of: try Data(contentsOf: url)))
        } catch let error as HistoryExport.ImportError {
            importReview = .failed(error.localizedDescription)
        } catch {
            importReview = .failed(String(localized: "The file couldn't be read."))
        }
    }

    private func restore(_ plan: HistoryExport.ImportPlan) {
        do {
            try services.importSessions(plan)
        } catch {
            Log.store.error("Restore failed: \(error, privacy: .public)")
            importReview = .failed(String(localized: "Nothing was restored. Try again."))
        }
    }

    private var importTitle: String {
        switch importReview {
        case .ready(let plan) where !plan.isEmpty: String(localized: "Restore this backup?")
        case .ready: String(localized: "Nothing to restore")
        case .failed: String(localized: "Can't restore")
        case nil: ""
        }
    }

    private func importMessage(_ review: ImportReview) -> String {
        switch review {
        case .failed(let message):
            return message
        case .ready(let plan) where plan.isEmpty && plan.skipped == 0:
            return String(localized: "Every session in this backup is already here.")
        case .ready(let plan):
            var lines = [
                String(localized: "\(plan.new.count) new sessions"),
                String(localized: "\(plan.updated.count) sessions updated"),
                String(localized: "\(plan.unchanged) already here"),
            ]
            if plan.skipped > 0 { lines.append(String(localized: "\(plan.skipped) skipped as unreadable")) }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: About

    private var about: some View {
        Section {
            LabeledContent {
                Text(version)
            } label: {
                RowLabel("Version", symbol: "info.circle")
            }
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

/// The two app icons side by side, each drawn as a small icon tile.
private struct AppIconPicker: View {
    let selection: AppIconChoice
    let choose: (AppIconChoice) -> Void
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 60

    var body: some View {
        HStack(spacing: Space.l) {
            ForEach(AppIconChoice.allCases) { choice in
                Button { choose(choice) } label: {
                    VStack(spacing: Space.xs) {
                        TickFigure(pose: choice.pose, palette: .icon(), detail: .simplified)
                            .padding(tile * 0.08)
                            .frame(width: tile, height: tile)
                            .background(TickPalette.standard.face, in: .rect(cornerRadius: tile * 0.225))
                            .overlay {
                                RoundedRectangle(cornerRadius: tile * 0.225 + 3)
                                    .strokeBorder(selection == choice ? Retro.orange : .clear, lineWidth: 2.5)
                                    .padding(-4)
                            }
                        Text(choice.title)
                            .font(.retro(.meta))
                            .foregroundStyle(selection == choice ? Retro.ink : Retro.inkSoft)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "App icon: \(choice.title)"))
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
    }
}

/// A settings row's words with a quiet symbol column in front, like
/// Opal's rows. Destructive rows tint the symbol too.
private struct RowLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = Retro.inkSoft
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    init(_ title: LocalizedStringKey, symbol: String, tint: Color = Retro.inkSoft) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(title)
        }
    }
}
