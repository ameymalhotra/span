import Foundation
import SwiftData

/// The two related models as shipped in 1.8.1, before WorkSession acquired
/// logTabID. Keep these frozen: using the current models to create an "old"
/// store would never exercise adding that column to an existing database.
enum PreLogSchema {
    @Model
    final class WorkSession {
        var id: UUID = UUID()
        var title: String = ""
        var category: String = "General"
        var plannedMinutes: Int = 60
        var startedAt: Date = Date.now
        var endedAt: Date?
        var pausedAt: Date?
        var totalPausedSeconds: TimeInterval = 0
        var statusRaw: String = "active"
        var focusRating: Int?
        var honestWorkMinutes: Int?
        var distractions: Int?
        var reflection: String?
        var reflectionStateRaw: String = "pending"
        @Relationship(deleteRule: .cascade, inverse: \SessionSegment.session)
        var segments: [SessionSegment] = []

        init(title: String, startedAt: Date) {
            self.title = title
            self.startedAt = startedAt
        }
    }

    @Model
    final class SessionSegment {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var session: WorkSession?

        init(startedAt: Date, endedAt: Date, session: WorkSession) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.session = session
        }
    }
}
