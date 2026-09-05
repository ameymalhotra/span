import SwiftUI

/// The colours categories can take.
enum CategoryPalette {

    struct Swatch: Identifiable {
        let slot: Int
        let name: String
        let light: UInt32
        let dark: UInt32
        var id: Int { slot }
        var color: Color { Color.adaptive(light: light, dark: dark) }
    }

    /// Seven hues, each authored separately for light and dark.
    ///
    /// The set and its order are not a matter of taste: they were checked with a
    /// colour-vision validator. Green beside pink is the classic deuteranope
    /// collision, so green sits between blue and purple, and orange and gold —
    /// which collide with each other — are pushed to opposite ends. An eighth
    /// hue could not be separated from its neighbour even under normal vision,
    /// so the palette is seven.
    static let swatches: [Swatch] = [
        Swatch(slot: 0, name: "Orange", light: 0xC25E12, dark: 0xD2731E),
        Swatch(slot: 1, name: "Teal",   light: 0x00909E, dark: 0x16A6BC),
        Swatch(slot: 2, name: "Pink",   light: 0xC8356E, dark: 0xE14D7E),
        Swatch(slot: 3, name: "Blue",   light: 0x2C6FD6, dark: 0x4A97F0),
        Swatch(slot: 4, name: "Green",  light: 0x1F8A4C, dark: 0x22A76A),
        Swatch(slot: 5, name: "Purple", light: 0x8A46CE, dark: 0x9E63E8),
        Swatch(slot: 6, name: "Gold",   light: 0x96780C, dark: 0xA98C0C),
    ]

    /// Reserved for uncategorised time. Outside the rotation deliberately: it is
    /// below the chroma floor and reads as grey, which is the point — absence of
    /// a category should not look like just another category.
    private static let neutral = (light: UInt32(0x5A6270), dark: UInt32(0x9BA4B4))

    /// Name → slot, refreshed from the store whenever categories change. Views
    /// resolve colours synchronously while drawing, so this cannot be a fetch.
    nonisolated(unsafe) private static var registry: [String: Int] = [:]

    static func updateRegistry(_ categories: [TimeCategory]) {
        registry = Dictionary(
            categories.map { ($0.name.trimmingCharacters(in: .whitespaces).lowercased(), $0.colorSlot) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func color(slot: Int) -> Color {
        let swatch = swatches[((slot % swatches.count) + swatches.count) % swatches.count]
        return swatch.color
    }

    static func color(for name: String?) -> Color {
        guard let name else { return neutralColor }
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return neutralColor }
        if let slot = registry[key] { return color(slot: slot) }
        // A category typed in freehand and never registered still gets a stable
        // colour rather than falling through to grey.
        return color(slot: hashedSlot(for: key))
    }

    static var neutralColor: Color {
        Color.adaptive(light: neutral.light, dark: neutral.dark)
    }

    /// Explicit FNV-1a rather than `hashValue`, which is seeded per process and
    /// would repaint every unregistered category on each launch.
    private static func hashedSlot(for name: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(swatches.count))
    }
}
