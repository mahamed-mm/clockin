// Siri's timer vocabulary (iOS 27's Clock domain): "set a 25-minute timer in
// Clockin", "pause my timer", "cancel the timer". Each maps onto the same
// app methods as the Shortcuts actions, so a timer here is a focus session.
// Built only with the iOS 27 SDK; older SDKs (CI's Xcode 26) skip the file.
#if compiler(>=6.4)
import AppIntents
import Foundation

@available(iOS 27, *)
@AppEnum(schema: .clock.timerState)
enum FocusTimerState: String, AppEnum {
    case running, paused, firing, undefined

    static let caseDisplayRepresentations: [FocusTimerState: DisplayRepresentation] = [
        .running: "Running",
        .paused: "Paused",
        .firing: "Time's up",
        .undefined: "Stopped",
    ]
}

/// The one session that can be running, as Siri's idea of a timer.
@available(iOS 27, *)
@AppEntity(schema: .clock.timer)
struct FocusTimerEntity: AppEntity {
    static let defaultQuery = FocusTimerQuery()

    var id: UUID
    @Property var duration: Duration
    @Property var durationRemaining: Duration
    @Property var isSleepTimer: Bool
    @Property var label: String?
    @Property var state: FocusTimerState

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label ?? Copy.focus)")
    }

    init(id: UUID) {
        self.id = id
    }

    /// The session saved in the App Group, as it stands at `now`.
    init(_ session: ActiveSession, now: Date = .now) {
        self.init(id: session.id)
        duration = .seconds(session.plannedDuration)
        durationRemaining = .seconds(session.remaining(at: now))
        isSleepTimer = false
        label = session.phase == .focus ? Copy.displayName(session.name) : Copy.breakAfter(session.name)
        state = session.isFinished(at: now) ? .firing : session.isPaused ? .paused : .running
    }

    /// The running session, if there is one.
    static func current() -> FocusTimerEntity? {
        DefaultsSessionStateStore().load().active.map { FocusTimerEntity($0) }
    }
}

@available(iOS 27, *)
struct FocusTimerQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [FocusTimerEntity] {
        FocusTimerEntity.current().map { [$0] }?.filter { identifiers.contains($0.id) } ?? []
    }

    func entities(matching string: String) async throws -> [FocusTimerEntity] {
        try await suggestedEntities()
    }

    func suggestedEntities() async throws -> [FocusTimerEntity] {
        FocusTimerEntity.current().map { [$0] } ?? []
    }
}

@available(iOS 27, *)
@AppIntent(schema: .clock.createTimer)
struct CreateFocusTimerIntent: AppIntent {
    @Parameter var duration: Duration
    @Parameter(default: false) var isSleepTimer: Bool
    @Parameter var label: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<FocusTimerEntity?> & ProvidesDialog {
        let minutes = Int((Double(duration.components.seconds) / 60).rounded())
        let outcome = await IntentBridge.startFocus?(minutes, label) ?? .nothingRunning
        return .result(value: FocusTimerEntity.current(), dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

@available(iOS 27, *)
@AppIntent(schema: .clock.pauseTimer)
struct PauseFocusTimerIntent: AppIntent {
    @Parameter var timer: FocusTimerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.pauseFocus?() ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

@available(iOS 27, *)
@AppIntent(schema: .clock.resumeTimer)
struct ResumeFocusTimerIntent: AppIntent {
    @Parameter var timer: FocusTimerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.resumeFocus?() ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

/// "Cancel my timer" follows Stop's rule: minutes already done are kept.
@available(iOS 27, *)
@AppIntent(schema: .clock.cancelTimer)
struct CancelFocusTimerIntent: AppIntent {
    @Parameter var entities: [FocusTimerEntity]

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.stopFocus?() ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}
#endif
