import Foundation
import SwiftData
import Testing
@testable import Span

// MARK: - Containers

/// Test stores. Nothing here ever touches the real store in
/// `~/Library/Application Support/TimeManager`.
@MainActor
enum TestStore {

    /// The usual choice: fast, isolated, thrown away with the test.
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: ModelStack.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A real SQLite store in a temporary directory, for durability tests that
    /// have to close a container and reopen it.
    static func onDisk(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: ModelStack.schema,
            configurations: ModelConfiguration(url: url)
        )
    }

    /// A fresh temporary directory, deleted when `body` returns.
    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpanTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}

// MARK: - Dates

/// A fixed clock. Tests that assert on durations must not race the wall clock,
/// and the app's date-taking APIs all accept an injected `now`/`at:`.
enum Clock {

    /// Wednesday 3 September 2025, 09:00 local. An ordinary day: no DST
    /// transition, mid-week, mid-month.
    static let reference: Date = date(2025, 9, 3, 9, 0)

    static let dayStart: Date = Calendar.current.startOfDay(for: reference)

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    /// Offsets from `dayStart`, so fixtures read as times of day.
    static func at(hour: Double) -> Date {
        dayStart.addingTimeInterval(hour * 3600)
    }

    static func minutes(_ count: Double) -> TimeInterval { count * 60 }
    static func hours(_ count: Double) -> TimeInterval { count * 3600 }
}

// MARK: - Fixtures

@MainActor
enum Fixture {

    /// A session with explicit segments, inserted into `context`.
    ///
    /// `segments` are `(start, end?)` pairs; a nil end leaves the run open, the
    /// way a running session is stored.
    @discardableResult
    static func session(
        in context: ModelContext,
        title: String = "Session",
        category: String = "Deep Work",
        plannedMinutes: Int = 60,
        startedAt: Date = Clock.reference,
        endedAt: Date? = nil,
        pausedAt: Date? = nil,
        totalPausedSeconds: TimeInterval = 0,
        status: SessionStatus = .completed,
        segments: [(Date, Date?)] = [],
        focusRating: Int? = nil,
        honestWorkMinutes: Int? = nil,
        distractions: Int? = nil,
        reflectionState: ReflectionState = .pending
    ) -> WorkSession {
        let session = WorkSession(title: title, category: category, plannedMinutes: plannedMinutes)
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.pausedAt = pausedAt
        session.totalPausedSeconds = totalPausedSeconds
        session.statusRaw = status.rawValue
        session.focusRating = focusRating
        session.honestWorkMinutes = honestWorkMinutes
        session.distractions = distractions
        session.reflectionStateRaw = reflectionState.rawValue
        context.insert(session)
        for (start, end) in segments {
            let segment = SessionSegment(startedAt: start, session: session)
            segment.endedAt = end
            session.segments.append(segment)
        }
        return session
    }

    @discardableResult
    static func entry(
        in context: ModelContext,
        title: String = "Entry",
        category: String = "Admin",
        from start: Date = Clock.reference,
        to end: Date = Clock.reference.addingTimeInterval(1800),
        notes: String? = nil
    ) -> TimeEntry {
        let entry = TimeEntry(title: title, category: category,
                              startedAt: start, endedAt: end, notes: notes)
        context.insert(entry)
        return entry
    }

    @discardableResult
    static func activity(
        in context: ModelContext,
        appName: String = "Xcode",
        bundleIdentifier: String? = "com.apple.dt.Xcode",
        windowTitle: String? = nil,
        url: String? = nil,
        from start: Date = Clock.reference,
        to end: Date = Clock.reference.addingTimeInterval(600),
        isIdle: Bool = false,
        categoryName: String? = "Building"
    ) -> ActivityRecord {
        let record = ActivityRecord(
            appName: appName, bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle, url: url,
            startedAt: start, endedAt: end,
            isIdle: isIdle, categoryName: categoryName
        )
        context.insert(record)
        return record
    }

    /// A detached block, for the pure layout and geometry tests. Not a stored
    /// model, so it needs no context and no actor.
    nonisolated static func block(
        _ title: String = "Block",
        kind: TimelineBlock.Kind = .entry,
        from start: Date,
        to end: Date,
        category: String? = "Deep Work",
        focusRating: Int? = nil
    ) -> TimelineBlock {
        TimelineBlock(
            id: "\(title)-\(start.timeIntervalSinceReferenceDate)",
            kind: kind, title: title, subtitle: category, category: category,
            start: start, end: end, focusRating: focusRating
        )
    }
}

// MARK: - String helpers

extension String {
    /// Modern locale data separates the time from AM/PM with a narrow no-break
    /// space (U+202F). Tests compare against ordinary spaces.
    var normalisingSpaces: String {
        replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
