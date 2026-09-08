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

    /// The part of the block that falls inside `range`.
    ///
    /// The same arithmetic `WorkSession.elapsed(in:)` does, and for the same
    /// reasons: a block belongs to the hours it actually covers, and a day
    /// total that is passed a range ending at "now" cannot count the part of a
    /// block that has not happened yet.
    func duration(in range: ClosedRange<Date>) -> TimeInterval {
        max(0, min(endedAt, range.upperBound).timeIntervalSince(max(startedAt, range.lowerBound)))
    }
}
