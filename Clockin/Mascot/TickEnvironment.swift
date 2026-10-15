import SwiftUI

extension EnvironmentValues {
    /// Stills Tick as Reduce Motion would, for the mascot gallery's switch;
    /// the system setting always applies as well.
    @Entry var tickReduceMotion = false
    /// The Focus screen's name field is being typed in: Tick glances at it.
    @Entry var tickWatchesName = false
    /// When the typed name last got a new symbol: Tick nods.
    @Entry var tickNodAt: Date? = nil
}
