import Foundation
import SwiftData

@Model
final class WorkSession {
    var id: UUID
    var title: String
    var category: String
    var plannedMinutes: Int
    var startedAt: Date
    var endedAt: Date?
    var pausedAt: Date?
    var totalPausedSeconds: TimeInterval
    var statusRaw: String
    var focusRating: Int?
    var honestWorkMinutes: Int?
    var distractions: Int?
    var reflection: String?

    init(title: String, category: String = "General", plannedMinutes: Int) {
        self.id = UUID()
        self.title = title
        self.category = category
        self.plannedMinutes = plannedMinutes
        self.startedAt = .now
        self.totalPausedSeconds = 0
        self.statusRaw = SessionStatus.active.rawValue
    }

    var status: SessionStatus { SessionStatus(rawValue: statusRaw) ?? .active }

    var plannedDuration: TimeInterval { TimeInterval(plannedMinutes * 60) }

    func elapsed(at date: Date = .now) -> TimeInterval {
        let end = endedAt ?? pausedAt ?? date
        return max(0, end.timeIntervalSince(startedAt) - totalPausedSeconds)
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        max(0, plannedDuration - elapsed(at: date))
    }

    func pause() {
        guard status == .active else { return }
        pausedAt = .now
        statusRaw = SessionStatus.paused.rawValue
    }

    func resume() {
        guard status == .paused, let pausedAt else { return }
        totalPausedSeconds += Date.now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
        statusRaw = SessionStatus.active.rawValue
    }

    func complete() {
        if status == .paused, let pausedAt {
            totalPausedSeconds += Date.now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        endedAt = .now
        statusRaw = SessionStatus.completed.rawValue
    }
}

enum SessionStatus: String, Codable {
    case active, paused, completed
}
