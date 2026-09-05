import Foundation
import SwiftData
import SwiftUI

/// A named kind of work, with a colour the user chooses.
///
/// Sessions and blocks keep storing their category as a plain `String` name;
/// this is the registry of known names and their colours, not a foreign key.
/// That keeps the change additive — existing records need no migration, and a
/// category typed in freehand still works, it just has no assigned colour until
/// it is added here.
@Model
final class TimeCategory {
    var id: UUID = UUID()
    var name: String = ""
    /// Index into the validated palette rather than a raw hex, so each category
    /// keeps a light and a dark variant instead of one colour that only works
    /// in one appearance.
    var colorSlot: Int = 0
    /// Set when the colour came from the wheel rather than the preset row;
    /// overrides `colorSlot` when present. Optional, so this stays an additive
    /// change to a store that already exists.
    var colorHex: String?
    var sortIndex: Int = 0

    /// The colour to draw. A custom hex is a single value used in both
    /// appearances — unavoidable when the user picks it themselves — whereas a
    /// preset keeps a separate light and dark variant.
    var resolvedColor: Color {
        if let colorHex, !colorHex.isEmpty { return Color(hexString: colorHex) }
        return CategoryPalette.color(slot: colorSlot)
    }

    init(name: String, colorSlot: Int, sortIndex: Int) {
        self.id = UUID()
        self.name = name
        self.colorSlot = colorSlot
        self.sortIndex = sortIndex
    }

    /// Seeded on first launch. One per palette slot, so the starting set is
    /// fully distinguishable; the user can rename, recolour, add and remove.
    static let defaults: [(String, Int)] = [
        ("Deep Work", 4),
        ("Meeting", 2),
        ("Meeting Focus", 5),
        ("Learning", 3),
        ("Admin", 6),
        ("Communication", 0),
        ("Break", 1),
    ]
}
