import Testing
import UIKit
@testable import Clockin

/// The bundled Fraunces cuts load, and their digits are tabular, so the
/// countdown doesn't shift sideways as it ticks.
@MainActor
struct FontTests {
    @Test(arguments: Fraunces.allCases)
    func cutIsRegistered(_ cut: Fraunces) throws {
        let font = try #require(UIFont(name: cut.rawValue, size: 40), "\(cut.rawValue) isn't registered")
        #expect(font.fontName == cut.rawValue)
    }

    @Test(arguments: Fraunces.allCases)
    func digitsAreTabular(_ cut: Fraunces) throws {
        let font = try #require(UIFont(name: cut.rawValue, size: 100))
        // Kerning included: the colon sits between digits in every countdown.
        func width(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }
        let reference = width("00:00")
        for sample in ["11:11", "24:48", "19:07", "88:88"] {
            #expect(abs(width(sample) - reference) < 0.01, "\(sample) in \(cut.rawValue)")
        }
    }

    @Test func fontFilesShipInTheWidgetToo() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugins.appendingPathComponent("ClockinWidgets.appex")))
        let fonts = try #require(widget.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
        for file in fonts {
            #expect(widget.url(forResource: file, withExtension: nil) != nil, "\(file) missing from the widget")
        }
        #expect(fonts.count == Fraunces.allCases.count)
    }
}
