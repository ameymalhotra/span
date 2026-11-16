import Foundation
import SwiftData

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
