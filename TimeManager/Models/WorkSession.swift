import Foundation
import SwiftData

@Model
final class WorkSession {
    var id: UUID = UUID()
    var title: String = ""
    var category: String = "General"
    var plannedMinutes: Int = 50
    var startedAt: Date = Date.now
    var endedAt: Date?
    var pausedAt: Date?
    var totalPausedSeconds: TimeInterval = 0
    var statusRaw: String = SessionStatus.active.rawValue
    var focusRating: Int?
    var honestWorkMinutes: Int?
    var distractions: Int?
    var reflection: String?
    /// Whether the user has been asked for a review and what they answered.
    /// Defaulted, so it migrates into the existing store without a custom stage.
    var reflectionStateRaw: String = ReflectionState.pending.rawValue

    /// The individual runs that make up this session. Added so the timeline can
    /// draw the time actually worked rather than one block spanning the breaks.
    /// Empty for sessions recorded before segments existed, which is why every
    /// reader below falls back to the legacy scalar arithmetic.
    @Relationship(deleteRule: .cascade, inverse: \SessionSegment.session)
    var segments: [SessionSegment] = []

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

    /// Time actually worked, excluding pauses.
    func elapsed(at date: Date = .now) -> TimeInterval {
        guard !segments.isEmpty else {
            // Legacy path for sessions recorded before segments.
            let end = endedAt ?? pausedAt ?? date
            return max(0, end.timeIntervalSince(startedAt) - totalPausedSeconds)
        }
        return segments.reduce(0) { $0 + $1.duration(at: date) }
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        max(0, plannedDuration - elapsed(at: date))
    }

    /// Wall-clock span from first start to last stop, breaks included. This is
    /// the extent the session occupies on the day, as distinct from `elapsed`.
    func span(at date: Date = .now) -> ClosedRange<Date> {
        let end = endedAt ?? date
        return startedAt...max(startedAt, end)
    }

    var reflectionState: ReflectionState {
        get { ReflectionState(rawValue: reflectionStateRaw) ?? .pending }
        set { reflectionStateRaw = newValue.rawValue }
    }

    /// True once the user has actually filled in the post-session review.
    var isReflected: Bool { reflectionState == .completed && focusRating != nil }

    /// Finished, but the user has not answered either way — the sheet is still
    /// owed. These must not be counted as "zero focus" in any summary.
    var needsReflection: Bool {
        status == .completed && reflectionState == .pending
    }

    /// The run currently in progress, if any.
    var openSegment: SessionSegment? {
        segments.first { $0.endedAt == nil }
    }

    // MARK: - Transitions

    func beginSegment(at date: Date = .now) {
        guard openSegment == nil else { return }
        segments.append(SessionSegment(startedAt: date, session: self))
    }

    private func closeSegment(at date: Date = .now) {
        openSegment?.endedAt = date
    }

    func pause() {
        guard status == .active else { return }
        pausedAt = .now
        closeSegment()
        statusRaw = SessionStatus.paused.rawValue
    }

    func resume() {
        guard status == .paused else { return }
        if let pausedAt {
            totalPausedSeconds += Date.now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        beginSegment()
        statusRaw = SessionStatus.active.rawValue
    }

    func complete(at date: Date = .now) {
        if status == .paused, let pausedAt {
            totalPausedSeconds += date.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        closeSegment(at: date)
        endedAt = date
        statusRaw = SessionStatus.completed.rawValue
    }
}

enum SessionStatus: String, Codable {
    case active, paused, completed
}

/// Distinguishes "never answered" from "declined to answer".
///
/// The review sheet used to be dismissible with no record either way, so a
/// session the user closed with Escape was indistinguishable from one they had
/// never been offered — and its nil fields quietly dragged every average down.
enum ReflectionState: String, Codable {
    case pending, completed, skipped
}
