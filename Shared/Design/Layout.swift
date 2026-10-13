import CoreGraphics

/// The spacing scale. Every gap and inset picks from here, so screens line
/// up with each other: the same gutter, the same gaps between sections.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Left and right edge of every screen's content.
    static let gutter: CGFloat = l
}

/// Corner radii for the few shapes that aren't capsules or circles.
enum Radius {
    /// Grouped rows inside a card sheet.
    static let card: CGFloat = 22
}
