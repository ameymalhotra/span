import SwiftUI

/// Maps a category name to a stable colour.
///
/// Categories are free text — the model has always stored a bare `String` — so
/// colours are assigned by hashing the name into a fixed palette rather than
/// stored per category. The same category therefore keeps its colour across
/// launches and across every view without any migration.
enum CategoryPalette {

    /// Seven hues, each authored separately for light and dark.
    ///
    /// The set and its order are not a matter of taste: they were checked with a
    /// colour-vision validator, and the order is what fixes the last failure.
    /// Green beside pink is the classic deuteranope collision (ΔE 3.5), so green
    /// sits between blue and purple, while orange and gold — which collide with
    /// each other — are pushed to opposite ends. Eight hues could not be
    /// separated at all; the eighth pair was indistinguishable even to normal
    /// vision, so the palette is seven.
    ///
    /// One adjacent pair (pink/teal) sits in the 6–8 ΔE band, which is only
    /// acceptable alongside a second, non-colour channel. Every surface that
    /// uses these provides one: timeline blocks carry a title and tooltip, and
    /// breakdown rows are labelled with the category name.
    private static let hues: [(light: UInt32, dark: UInt32)] = [
        (0xC25E12, 0xD2731E),   // orange
        (0x00909E, 0x16A6BC),   // teal
        (0xC8356E, 0xE14D7E),   // pink
        (0x2C6FD6, 0x4A97F0),   // blue
        (0x1F8A4C, 0x22A76A),   // green
        (0x8A46CE, 0x9E63E8),   // purple
        (0x96780C, 0xA98C0C),   // gold
    ]

    /// Reserved for uncategorised time. Deliberately outside the rotation: it is
    /// below the chroma floor and reads as grey, which is the point — absence of
    /// a category should not look like just another category.
    private static let neutral = (light: UInt32(0x5A6270), dark: UInt32(0x9BA4B4))

    /// Fixed slots for the categories the app itself produces.
    ///
    /// Hashing alone is not enough: seven slots and eight built-in categories
    /// means collisions are guaranteed by pigeonhole, and in practice they
    /// clustered badly — four of the built-ins landed on gold. Pinning the
    /// common ones guarantees the categories a real day is mostly made of are
    /// all distinguishable, and leaves hashing to cover the long tail.
    private static let fixed: [String: Int] = [
        "deep work": 4,   // green
        "building": 3,    // blue
        "talking": 0,     // orange
        "meetings": 2,    // pink
        "browsing": 1,    // teal
        "reading": 5,     // purple
        "designing": 6,   // gold
    ]

    static func color(for name: String?) -> Color {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Color.adaptive(light: neutral.light, dark: neutral.dark)
        }
        let hue = hues[slot(for: name)]
        return Color.adaptive(light: hue.light, dark: hue.dark)
    }

    private static func slot(for name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return fixed[key] ?? index(for: name)
    }

    /// Stable index derived from the name. Uses an explicit FNV-1a hash rather
    /// than `hashValue`, which is seeded per process and would repaint every
    /// category on each launch.
    private static func index(for name: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(hues.count))
    }
}
