import Testing
import UIKit
@testable import Clockin

/// Every colour that carries words is readable on both paper tones: WCAG AA
/// (4.5:1) normally, AAA (7:1) with Increase Contrast, in light and dark.
@MainActor
struct ContrastTests {
    struct Appearance: CustomStringConvertible, Sendable {
        var style: UIUserInterfaceStyle
        var contrast: UIAccessibilityContrast
        var description: String {
            "\(style == .dark ? "dark" : "light")\(contrast == .high ? " + high contrast" : "")"
        }
    }

    nonisolated static let appearances = [UIUserInterfaceStyle.light, .dark].flatMap { style in
        [UIAccessibilityContrast.normal, .high].map { Appearance(style: style, contrast: $0) }
    }

    func color(_ name: String, _ appearance: Appearance) throws -> UIColor {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = appearance.style
            traits.accessibilityContrast = appearance.contrast
        }
        let color = try #require(UIColor(named: name, in: Bundle(for: AppServices.self), compatibleWith: traits),
                                 "No colour named \(name)")
        return color.resolvedColor(with: traits)
    }

    @Test(arguments: appearances)
    func textIsReadableOnPaper(_ appearance: Appearance) throws {
        let minimum = appearance.contrast == .high ? 7.0 : 4.5
        for background in [Retro.Asset.paper, Retro.Asset.paperDeep] {
            let paper = try color(background, appearance)
            for text in Retro.Asset.text {
                let ratio = Self.contrast(try color(text, appearance), paper)
                #expect(ratio >= minimum, "\(text) on \(background), \(appearance): \(ratio)")
            }
        }
    }

    @Test func contrastMathMatchesWCAG() {
        #expect(abs(Self.contrast(.black, .white) - 21) < 0.01)
        #expect(Self.contrast(.white, .white) == 1)
    }

    static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
