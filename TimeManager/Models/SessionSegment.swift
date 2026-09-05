import Foundation
import SwiftData

/// One continuous run of a `WorkSession`.
///
/// `WorkSession` collapses all its pauses into a single `totalPausedSeconds`
/// scalar, which is enough to compute a duration but not to draw one: a block
/// spanning `startedAt...endedAt` silently includes the breaks, and the holes
/// where the user paused cannot be rendered at all. Segments record each run as
/// a real interval so the timeline can draw exactly the time that was worked.
@Model
final class SessionSegment {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    /// `nil` while this segment is the one currently running.
    var endedAt: Date?
    var session: WorkSession?

    init(startedAt: Date = .now, session: WorkSession? = nil) {
        self.id = UUID()
        self.startedAt = startedAt
        self.session = session
    }

    func duration(at date: Date = .now) -> TimeInterval {
        max(0, (endedAt ?? date).timeIntervalSince(startedAt))
    }
}
