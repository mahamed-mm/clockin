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
                BedsideView(session: session, day: services.today)
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
                VStack(spacing: 10) {
                    nameField
                        .glassEffectID("session", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                    RecentNames(typed: sessionName) { sessionName = $0 }
                }
            case .active(let session):
                SessionChip(session: session)
                    .glassEffectID("session", in: glass)
                    .glassEffectTransition(.matchedGeometry)
            case .focusComplete(let focus):
                CompletionSummary(focus: focus, day: services.today)
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
            .onChange(of: sessionName) { _, name in
                // The engine caps names too; this keeps the field honest about it.
                if name.count > ActiveSession.maxNameLength {
                    sessionName = String(name.prefix(ActiveSession.maxNameLength))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Session name")
    }

    // MARK: Controls

    private var controls: some View {
        let idle = engine.stage == .idle
        let undoable = idle && engine.undoableCancel != nil
        return VStack(spacing: 10) {
            primaryButton
            ZStack {
                secondaryRow
                // Laid out in every stage, shown only when idle, so the slot
                // keeps its height on Start and Cancel even when the hint wraps.
                AlertHint(status: services.alertStatus)
                    .opacity(idle && !undoable ? 1 : 0)
                    .allowsHitTesting(idle && !undoable)
                    .accessibilityHidden(!idle || undoable)
                // Takes Cancel's place for a few seconds, right under the finger.
                UndoBar(message: String(localized: "Session cancelled"),
                        hint: String(localized: "Brings the session back"), undo: engine.undoCancel)
                    .opacity(undoable ? 1 : 0)
                    .allowsHitTesting(undoable)
                    .accessibilityHidden(!undoable)
            }
            .animation(Motion.calm(reduceMotion), value: undoable)
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
            (String(localized: "Start focus"), "play.fill", start)
        case .active(let session):
            session.isPaused
                ? (String(localized: "Resume"), "play.fill", engine.resume)
                : (String(localized: "Pause"), "pause.fill", engine.pause)
        case .focusComplete(let focus):
            (Copy.startBreak(seconds: engine.breakLength(after: focus)), "cup.and.saucer.fill", engine.startBreak)
        }
    }

    /// Quiet text buttons under the primary action. Always the same height
    /// so the layout doesn't jump between states.
    @ViewBuilder
    private var secondaryRow: some View {
        if case .active(let session) = engine.stage, session.phase == .focus {
            // Redraws only when Finish now unlocks.
            let schedule = TickSchedule(wakeDates: engine.controlChanges(after: .now))
            TimelineView(schedule) { context in
                let canFinish = engine.canFinishEarly(at: context.date)
                HStack(spacing: 28) {
                    quietButton(String(localized: "Cancel session"), role: .destructive, action: engine.cancel)
                    quietButton(Copy.finishNow, action: engine.finishEarly)
                        .disabled(!canFinish)
                        .opacity(canFinish ? 1 : 0.45)
                        .accessibilityHint(String(localized: "Ends the session and keeps the minutes"))
                }
            }
            .id(schedule)
        } else {
            let action = secondaryAction
            quietButton(action.title ?? " ", role: action.role) { action.run?() }
                .opacity(action.title == nil ? 0 : 1)
                .disabled(action.title == nil)
                .accessibilityHidden(action.title == nil)
        }
    }

    private func quietButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            // The frame sits inside the label so the whole 44 pt row takes the tap.
            Text(title)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .font(.retro(.body))
        .foregroundStyle(Retro.inkSoft)
        .buttonStyle(.borderless)
    }

    private var secondaryAction: (title: String?, role: ButtonRole?, run: (() -> Void)?) {
        switch engine.stage {
        case .idle:
            (nil, nil, nil)
        case .active:
            (String(localized: "Skip break"), nil, engine.skipBreak)
        case .focusComplete:
            // Moving on without a break isn't skipping anything that started.
            (String(localized: "Done for now"), nil, engine.skipBreak)
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
