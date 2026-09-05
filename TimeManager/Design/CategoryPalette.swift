import SwiftUI

/// Maps a category name to a stable colour.
///
/// Categories are free-text (the model has always stored a bare `String`), so
/// colours are assigned by hashing the name into a fixed palette. The same
/// category therefore keeps its colour across launches without needing a
/// stored colour per category, while explicitly configured categories can
/// still override it.
enum CategoryPalette {

    /// Eight hues, each tuned separately for light and dark. They are spread
    /// around the wheel so adjacent timeline blocks stay distinguishable.
    private static let hues: [(light: UInt32, dark: UInt32)] = [
        (0x2F7DE1, 0x5AA9FF),   // blue
        (0x1F9B79, 0x35D6AA),   // green
        (0xC2591B, 0xFF9F45),   // orange
        (0x8B4CC9, 0xC08BFF),   // purple
        (0xC0396B, 0xFF6F9C),   // pink
        (0x0E8C9B, 0x3BD0E3),   // teal
        (0x9A7B12, 0xE0BE3A),   // gold
        (0x5A6270, 0x9BA4B4),   // slate
    ]

    /// Colour for a category name. Empty or uncategorised input gets slate.
    static func color(for name: String?) -> Color {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Color.adaptive(light: hues[7].light, dark: hues[7].dark)
        }
        let hue = hues[index(for: name)]
        return Color.adaptive(light: hue.light, dark: hue.dark)
    }

    /// Stable index derived from the name. Uses an explicit FNV-1a hash rather
    /// than `hashValue`, which is seeded per-process and would give a category
    /// a different colour on every launch.
    private static func index(for name: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(hues.count))
    }
}
