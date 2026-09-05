import SwiftUI

/// Design tokens for the app.
///
/// Light and dark are authored independently rather than inverted: light keeps
/// its greys close together and lets ambient contrast do the work, while dark
/// spreads its levels further apart and lifts chroma so colours survive the
/// lower ambient light.
enum Theme {

    // MARK: - Palette

    /// Teal accent. Distinct from the system blue so selection still reads as
    /// "this app" rather than "a stock control".
    static let accent = Color.adaptive(light: 0x0E8C7C, dark: 0x2FD3BC)
    static let accentMuted = Color.adaptive(light: 0x0E8C7C, dark: 0x2FD3BC).opacity(0.14)

    /// Label colour for anything filled with `accent`.
    ///
    /// The dark accent is a light teal — correct as a fill or stroke against a
    /// dark surface, but white text on it lands around 1.9:1. Prominent buttons
    /// take a dark label in dark mode instead.
    static let onAccent = Color.adaptive(light: 0xFFFFFF, dark: 0x0B2E29)

    /// The now-indicator. Deliberately the one hot colour in the timeline.
    static let now = Color.adaptive(light: 0xE0322A, dark: 0xFF544A)

    /// The floating HUD's palette.
    ///
    /// Fixed rather than adaptive: the pill forces a dark appearance because it
    /// floats over the desktop rather than sitting inside the app's surfaces,
    /// so there is no light variant to author. It holds to the app's own two
    /// colours — white at a few weights, teal for the live number — so the pill
    /// reads as part of Span rather than a second app parked on top.
    enum HUD {
        static let value = Color.white.opacity(0.92)
        static let caption = Color.white.opacity(0.45)
        /// The dark-appearance `accent`, stated outright since the HUD never
        /// resolves against the light one.
        static let accent = Color(rgbHex: 0x2FD3BC)
        /// Dividers, the target ring's unfilled track, and the hairline border.
        static let line = Color.white.opacity(0.16)
    }

    // MARK: - Surfaces

    /// Window background behind the timeline and summary panes.
    static let canvas = Color.adaptive(light: 0xFFFFFF, dark: 0x1B1B1D)
    /// Raised panels sitting on the canvas.
    static let surface = Color.adaptive(light: 0xF7F7F9, dark: 0x252528)
    /// Cards and timeline blocks.
    static let raised = Color.adaptive(light: 0xFFFFFF, dark: 0x2E2E32)

    // MARK: - Text

    static let label = Color.adaptive(light: 0x1D1D1F, dark: 0xF2F2F5)
    static let secondaryLabel = Color.adaptive(light: 0x6B6B72, dark: 0x9A9AA2)
    static let tertiaryLabel = Color.adaptive(light: 0xA1A1A9, dark: 0x66666E)

    // MARK: - Lines

    /// Hairline separators and the timeline's hour rules.
    static let hairline = Color.adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.10)
    /// Half-hour rules — deliberately fainter than the hour rules.
    static let hairlineFaint = Color.adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.05)

    // MARK: - Metrics

    /// 8pt base grid, matching macOS convention.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Inset around a pane's content. Deliberately larger than xxl:
        /// content pressed against the toolbar reads as cramped.
        static let page: CGFloat = 36
    }

    enum Radius {
        static let block: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 12
        static let pill: CGFloat = 999
    }

    /// macOS uses noticeably smaller type than iOS or the web; 13pt is body.
    enum Font {
        static let statValue = SwiftUI.Font.system(size: 24, weight: .semibold).monospacedDigit()
        static let timer = SwiftUI.Font.system(size: 64, weight: .thin, design: .rounded).monospacedDigit()
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11)
        static let micro = SwiftUI.Font.system(size: 9, weight: .medium)
        static let gutter = SwiftUI.Font.system(size: 10, weight: .medium).monospacedDigit()
        static let blockTitle = SwiftUI.Font.system(size: 11, weight: .medium)
    }
}

// MARK: - Colour helpers

extension Color {
    /// Builds a colour that resolves differently per appearance, so light and
    /// dark can be tuned separately instead of one being derived from the other.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }

    init(rgbHex hex: UInt32) {
        self.init(nsColor: NSColor(rgbHex: hex))
    }

    /// Parses `#RRGGBB` / `RRGGBB`, falling back to grey on malformed input so a
    /// bad stored category colour can never crash rendering.
    init(hexString: String) {
        var trimmed = hexString.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            self = .gray
            return
        }
        self.init(rgbHex: value)
    }
}

extension Color {
    /// `#RRGGBB` for persistence. Nil when the colour has no sRGB
    /// representation, which a picked colour always does.
    var hexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((srgb.redComponent * 255).rounded()),
                      Int((srgb.greenComponent * 255).rounded()),
                      Int((srgb.blueComponent * 255).rounded()))
    }
}

extension NSColor {
    convenience init(rgbHex hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
