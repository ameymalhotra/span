import Foundation
import SwiftData
import SwiftUI

/// One thing you keep coming back to — a course, a paper, a client — with its
/// own running log of where you stopped and what to do next.
///
/// Tabs are flat. `group` is a label for the Log sidebar's headings and
/// nothing else: it holds no entries and has no settings, which is why it is a
/// plain string here rather than a model of its own — the same choice sessions
/// make for their category.
@Model
final class LogTab {
    var id: UUID = UUID()
    var name: String = ""
    /// Empty when the tab sits under no heading.
    var group: String = ""
    /// Index into `CategoryPalette.swatches`, so a tab's colour has a light and
    /// a dark variant like every category does.
    var colorSlot: Int = 0
    var sortIndex: Int = 0
    /// Hidden from the pickers on the start sheet, review sheet and menu bar,
    /// but kept — with its whole history — in the Log pane.
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \LogEntry.tab)
    var entries: [LogEntry] = []

    init(name: String, group: String = "", colorSlot: Int = 0, sortIndex: Int = 0, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.group = group
        self.colorSlot = colorSlot
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    var color: Color { CategoryPalette.color(slot: colorSlot) }
}
