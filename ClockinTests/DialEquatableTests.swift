import Foundation
import Testing
@testable import Clockin

/// The dial and Tick are equal while they'd draw the same, so the focus
/// screen changing for something else (a tap, a letter typed) leaves them
/// alone. The crown's closure is new on every pass and doesn't count.
@MainActor
struct DialEquatableTests {
    private func crown(_ label: String) -> (label: String, action: () -> Void) {
        (label, {})
    }

    @Test func tickIgnoresNewClosures() {
        let a = TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"), onDismiss: {})
        let b = TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"), onDismiss: {})
        #expect(a == b)
    }

    @Test func tickChangesWithWhatItDraws() {
        let base = TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"))
        #expect(base != TickView(pose: .waiting, progress: .fixed(0.4), crown: crown("Pause")))
        #expect(base != TickView(pose: .working, progress: .fixed(0.5), crown: crown("Pause")))
        #expect(base != TickView(pose: .working, progress: .fixed(0.4), crown: crown("Resume")))
        #expect(base != TickView(pose: .working, progress: .fixed(0.4), crown: nil))
        #expect(base != TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"), onDismiss: {}))
        #expect(base != TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"), caughtAt: .now))
        #expect(base != TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"), attention: .nameField))
        #expect(base != TickView(pose: .working, progress: .fixed(0.4), crown: crown("Pause"), listening: false))
    }
}
