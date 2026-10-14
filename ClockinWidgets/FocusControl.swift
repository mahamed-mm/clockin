import AppIntents
import SwiftUI
import WidgetKit

/// One button for Control Center, the Lock Screen and the Action button. It
/// does what the big button in the app would: start focus, pause, resume, or
/// start the break.
struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlFace.kind, provider: Provider()) { face in
            ControlWidgetButton(action: FocusButtonIntent()) {
                Label(face.title, systemImage: face.symbol)
            }
        }
        .displayName("Focus")
        .description("Start focus, pause or resume it, or start the break.")
    }

    /// Read from the session state the app saves in the App Group.
    struct Provider: ControlValueProvider {
        var previewValue: ControlFace { .start }

        func currentValue() async throws -> ControlFace {
            ControlFace(state: DefaultsSessionStateStore().load(), now: .now)
        }
    }
}
