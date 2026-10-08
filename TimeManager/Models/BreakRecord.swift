import Foundation
import SwiftData

/// A break the user took, kept so the timeline can draw it.
///
/// The running break lives on `AppModel` as a deadline, which is all its clock
/// needs — but a deadline is gone the moment the break ends, and the hole it
/// leaves in the day reads as time unaccounted for rather than time spent
/// resting. Recording it as an interval puts the rest on the day beside the
/// work around it. It counts towards nothing.
@Model
final class BreakRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    /// `nil` while the break is running.
    var endedAt: Date?
    /// When the break is due to end. Lets a running break be drawn to the end
    /// of its time, and lets one the app quit during be closed where it was
    /// meant to stop rather than left open for ever.
    var plannedEnd: Date = Date.now

    init(startedAt: Date, plannedEnd: Date) {
        self.id = UUID()
        self.startedAt = startedAt
        self.plannedEnd = plannedEnd
    }

    /// Where the break stops on the timeline: when it ended, or when it is due to.
    var end: Date { endedAt ?? plannedEnd }
}
