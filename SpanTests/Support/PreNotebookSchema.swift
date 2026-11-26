import Foundation
import SwiftData
import SwiftUI
@testable import Span

/// Frozen Span 1.9 models: migration must start without any notebook fields.
enum PreNotebookSchema {
    
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
    
    /// One handoff: where you stopped, and what you got done.
    ///
    /// The fields mirror the Google Doc this replaces — a date and time, a
    /// "Resume point / Things to do", and "What was done in this session". Either
    /// text may be empty, but not both: on a rushed day the resume point alone is
    /// a complete entry.
    @Model
    final class LogEntry {
        var id: UUID = UUID()
        var tab: LogTab?
        /// When the entry was saved. Editable, so entries carried over from the old
        /// Doc can keep the dates they were written on.
        var recordedAt: Date = Date.now
        var editedAt: Date?
        var resumePoint: String = ""
        var done: String = ""
    
        /// The session this entry was written about, if one was running or had
        /// just finished. An ID rather than a relationship, so deleting a session
        /// never takes a log entry with it.
        var sessionID: UUID?
        /// Copied at save time, so the entry still reads correctly after the
        /// session is renamed or deleted.
        var sessionTitle: String?
        /// Time worked in that session when the entry was saved. Nil when no timer
        /// was involved — the log never invents a duration.
        var workedSeconds: Double?
    
        init(tab: LogTab?, recordedAt: Date = .now, resumePoint: String, done: String) {
            self.id = UUID()
            self.tab = tab
            self.recordedAt = recordedAt
            self.resumePoint = resumePoint
            self.done = done
        }
    
        var hasResumePoint: Bool { !resumePoint.isEmpty }
        var hasDone: Bool { !done.isEmpty }
    }
}
