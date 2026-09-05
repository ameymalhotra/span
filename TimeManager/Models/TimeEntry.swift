import Foundation
import SwiftData

/// A time block the user creates or edits by hand, the way you would in a
/// calendar. Complements the two automatic sources: it covers work that
/// happened away from the machine, and lets a mis-tracked stretch be corrected
/// without touching the underlying activity records.
@Model
final class TimeEntry {
    var id: UUID = UUID()
    var title: String = ""
    var category: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date = Date.now
    var notes: String?

    init(title: String, category: String = "", startedAt: Date, endedAt: Date, notes: String? = nil) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
    }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}
