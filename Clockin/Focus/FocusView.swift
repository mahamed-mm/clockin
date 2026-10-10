import SwiftData
import SwiftUI

struct FocusView: View {
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("lastSessionName") private var sessionName = ""
    @FocusState private var nameFocused: Bool
    @Namespace private var glass

    /// iPhone on its side during a session: switch to the bedside layout.
    private var bedsideSession: ActiveSession? {
        verticalSizeClass == .compact ? engine.active : nil
    }

    var body: some View {
        Group {
            if let session = bedsideSession {
                BedsideView(session: session)
                    .transition(.opacity)
            } else {
                standardLayout
            }
        }
        .toolbar(bedsideSession == nil ? .visible : .hidden, for: .tabBar)
        .onChange(of: bedsideSession != nil, initial: true) { _, isBedside in
            // Keep the screen on while the phone is used as a bedside clock.
            UIApplication.shared.isIdleTimerDisabled = isBedside
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(trigger: services.lastEvent) { _, stamp in stamp.feedback }
        .animation(Motion.calm(reduceMotion), value: engine.stage)
        .animation(Motion.calm(reduceMotion), value: bedsideSession != nil)
    }

    private var standardLayout: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 640 || geo.size.width > geo.size.height * 1.15
            ZStack {
                PaperBackground(wash: wash)
                    .animation(Motion.tint(reduceMotion), value: engine.stage)
                    .onTapGesture { nameFocused = false }
                if wide {
                    HStack(spacing: 48) {
                        flexibleDial
                            .padding(.vertical, 24)
                        VStack(alignment: .leading, spacing: 28) {
                            FocusHeader(stage: engine.stage)
                            sessionSlot
                            controls
                        }
                        .frame(maxWidth: 380)
                    }
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 24) {
                        FocusHeader(stage: engine.stage)
                        flexibleDial
                        sessionSlot
                        controls
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A soft colour wash at the top of the page for each phase.
    private var wash: Color? {
        switch engine.stage {
        case .idle: nil
        case .active(let session): Retro.tint(for: session.phase)
        case .focusComplete: Retro.mustard
        }
    }

    /// The dial takes whatever space the header and controls leave, so the
    /// layout holds up on short folded screens and while a scene is resized.
    private var flexibleDial: some View {
        GeometryReader { proxy in
            DialFace(stage: engine.stage,
                     size: max(0, min(proxy.size.width, proxy.size.height)),
                     celebration: services.celebrations)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 160)
    }

    // MARK: Session slot

    /// Name field → session chip → completion summary. The field and chip
    /// share a Liquid Glass identity so one morphs into the other.
    @ViewBuilder
    private var sessionSlot: some View {
        GlassEffectContainer {
            switch engine.stage {
            case .idle:
                nameField
                    .glassEffectID("session", in: glass)
                    .glassEffectTransition(.matchedGeometry)
            case .active(let session):
                SessionChip(session: session)
                    .glassEffectID("session", in: glass)
                    .glassEffectTransition(.matchedGeometry)
            case .focusComplete(let name):
                CompletionSummary(name: name)
            }
        }
    }

    private var nameField: some View {
        TextField("What are you focusing on?", text: $sessionName)
            .font(.retro(.body))
            .foregroundStyle(Retro.ink)
            .submitLabel(.go)
            .focused($nameFocused)
            .onSubmit(start)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Session name")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            primaryButton
            ZStack {
                secondaryButton
                // Laid out in every stage, shown only when idle, so the slot
                // keeps its height on Start and Cancel even when the hint wraps.
                AlertHint(status: services.alertStatus)
                    .opacity(engine.stage == .idle ? 1 : 0)
                    .allowsHitTesting(engine.stage == .idle)
                    .accessibilityHidden(engine.stage != .idle)
            }
        }
    }

    private var primaryButton: some View {
        let (title, symbol, action) = primaryAction
        return Button(action: action) {
            Label {
                Text(title).contentTransition(.interpolate)
            } icon: {
                Image(systemName: symbol).contentTransition(.symbolEffect(.replace))
            }
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .tint(buttonTint)
        .animation(Motion.tint(reduceMotion), value: engine.stage)
    }

    private var buttonTint: Color {
        switch engine.stage {
        case .idle: Retro.orange
        case .active(let session): Retro.tint(for: session.phase)
        case .focusComplete: Retro.avocado
        }
    }

    private var primaryAction: (String, String, () -> Void) {
        switch engine.stage {
        case .idle:
            ("Start focus", "play.fill", start)
        case .active(let session):
            session.isPaused
                ? ("Resume", "play.fill", engine.resume)
                : ("Pause", "pause.fill", engine.pause)
        case .focusComplete:
            ("Start \(breakLength) break", "cup.and.saucer.fill", engine.startBreak)
        }
    }

    /// Quiet text button under the primary action. Always takes the same
    /// height so the layout doesn't jump between states.
    private var secondaryButton: some View {
        let action = secondaryAction
        return Button(action.title ?? " ", role: action.role) { action.run?() }
            .font(.retro(.body))
            .foregroundStyle(Retro.inkSoft)
            .buttonStyle(.borderless)
            .frame(minHeight: 32)
            .opacity(action.title == nil ? 0 : 1)
            .disabled(action.title == nil)
            .accessibilityHidden(action.title == nil)
    }

    /// "5-min", or "5-sec" with debug test timers.
    private var breakLength: String {
        let seconds = Int(Durations.duration(for: .rest))
        return seconds >= 60 ? "\(seconds / 60)-min" : "\(seconds)-sec"
    }

    private var secondaryAction: (title: String?, role: ButtonRole?, run: (() -> Void)?) {
        switch engine.stage {
        case .idle:
            (nil, nil, nil)
        case .active(let session) where session.phase == .focus:
            ("Cancel session", .destructive, engine.cancel)
        case .active, .focusComplete:
            ("Skip break", nil, engine.skipBreak)
        }
    }

    private func start() {
        nameFocused = false
        engine.start(name: sessionName)
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(AppServices.preview)
        .environment(AppServices.preview.engine)
        .modelContainer(AppServices.preview.container)
}
#endif
