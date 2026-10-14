import SwiftUI
import Testing
@testable import Clockin

/// The paper's grain: faint, fainter on dark paper, gone with Increase Contrast.
struct PaperGrainTests {
    @Test func faintAndOffWithIncreaseContrast() {
        let light = PaperGrain.amount(scheme: .light, contrast: .standard)
        let dark = PaperGrain.amount(scheme: .dark, contrast: .standard)
        #expect(light > dark && dark > 0)
        #expect(light < 0.04)
        #expect(PaperGrain.amount(scheme: .light, contrast: .increased) == 0)
        #expect(PaperGrain.amount(scheme: .dark, contrast: .increased) == 0)
    }
}
