import AppIntents
import SwiftUI
import WidgetKit

/// Opens Clockin straight to the park field, for a thought mid-session.
struct ParkControl: ControlWidget {
    static let kind = "ParkControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "clockin://park")!)) {
                Label("Park a Thought", systemImage: "note.text")
            }
        }
        .displayName("Park a Thought")
        .description("Opens Clockin to put a thought aside for after the session.")
    }
}
