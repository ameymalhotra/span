import SwiftUI

/// One drawable span on the day timeline.
///
/// The timeline draws three different records — sessions, hand-made entries and
/// passively tracked app activity — so they are normalised into this single
/// value type up front. Views then lay out and hit-test one homogeneous
/// collection instead of branching per source at every step.
struct TimelineBlock: Identifiable, Hashable {

    enum Kind: Hashable {
        /// A timed focus session.
        case session
        /// A block the user wrote by hand.
        case entry
        /// Passively tracked app usage.
        case activity
        /// Time away from the keyboard.
        case idle

        /// Activity and idle are drawn as a thin continuous ribbon beside the
        /// gutter; sessions and entries get the full-width card treatment. The
        /// split keeps "what I meant to do" visually separate from "what
        /// actually had focus".
        var isRibbon: Bool { self == .activity || self == .idle }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let category: String?
    let start: Date
    let end: Date
    /// Focus rating 1...5 for reflected sessions, else nil.
    let focusRating: Int?

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    var color: Color {
        switch kind {
        case .idle: return Theme.tertiaryLabel
        case .activity, .session, .entry: return CategoryPalette.color(for: category ?? title)
        }
    }
}

extension TimelineBlock {

    /// Builds the blocks for a session. A session with recorded segments
    /// contributes one block per segment, so pauses read as real gaps; older
    /// sessions without segments fall back to a single spanning block.
    static func blocks(for session: WorkSession, now: Date = .now) -> [TimelineBlock] {
        let category = session.category.isEmpty ? nil : session.category
        guard !session.segments.isEmpty else {
            return [TimelineBlock(
                id: "session-\(session.id)",
                kind: .session,
                title: session.title,
                subtitle: category,
                category: category,
                start: session.startedAt,
                end: session.endedAt ?? now,
                focusRating: session.focusRating
            )]
        }
        // Segments closer together than this are one block. Drawing a card per
        // segment turns a session you paused briefly into two identical cards,
        // which reads as a duplicate rather than as a pause.
        let mergeGap: TimeInterval = 10 * 60
        // A running session extends to when it is due to end rather than
        // stopping at the current minute, so its remaining time is visible on
        // the timeline and its end can be dragged.
        let openEnd = session.status == .active
            ? now.addingTimeInterval(session.remaining(at: now))
            : now
        var runs: [(start: Date, end: Date)] = []
        for segment in session.segments.sorted(by: { $0.startedAt < $1.startedAt }) {
            let end = segment.endedAt ?? openEnd
            if var last = runs.last, segment.startedAt.timeIntervalSince(last.end) <= mergeGap {
                last.end = max(last.end, end)
                runs[runs.count - 1] = last
            } else {
                runs.append((segment.startedAt, end))
            }
        }
        return runs.enumerated().map { index, run in
            TimelineBlock(
                id: "session-\(session.id)-\(index)",
                kind: .session,
                title: session.title,
                subtitle: category,
                category: category,
                start: run.start,
                end: run.end,
                focusRating: session.focusRating
            )
        }
    }

    static func block(for entry: TimeEntry) -> TimelineBlock {
        TimelineBlock(
            id: "entry-\(entry.id)",
            kind: .entry,
            title: entry.title,
            subtitle: entry.category.isEmpty ? nil : entry.category,
            category: entry.category.isEmpty ? nil : entry.category,
            start: entry.startedAt,
            end: entry.endedAt,
            focusRating: nil
        )
    }

    /// Merges consecutive records for the same app into one block.
    ///
    /// The tracker writes a record per app or title change, so a morning in one
    /// editor becomes dozens of rows. Drawn literally they are unreadable
    /// slivers; merged, they read as the band of time they actually were.
    static func mergedActivityBlocks(
        _ records: [ActivityRecord],
        grouping: TimelineGrouping = .category,
        gapTolerance: TimeInterval = 90
    ) -> [TimelineBlock] {
        func group(_ record: ActivityRecord) -> String {
            guard !record.isIdle else { return "Away" }
            switch grouping {
            case .app: return record.appName
            case .category:
                return ActivityRecord.currentCategory(for: record)
            }
        }

        let sorted = records.sorted { $0.startedAt < $1.startedAt }
        var merged: [TimelineBlock] = []
        var run: (record: ActivityRecord, start: Date, end: Date)?

        func flush() {
            guard let run else { return }
            let name = group(run.record)
            merged.append(TimelineBlock(
                id: "activity-\(run.record.id)",
                kind: run.record.isIdle ? .idle : .activity,
                title: name,
                // In category mode the app is still worth naming, since the
                // group alone does not say which one you were in.
                subtitle: [grouping == .category ? run.record.appName : nil,
                           run.record.windowTitle ?? run.record.url]
                    .compactMap { $0 }.joined(separator: " · "),
                category: name,
                start: run.start,
                end: run.end,
                focusRating: nil
            ))
        }

        for record in sorted {
            if var open = run,
               group(open.record) == group(record),
               open.record.isIdle == record.isIdle,
               record.startedAt.timeIntervalSince(open.end) <= gapTolerance {
                open.end = max(open.end, record.endedAt)
                run = open
                continue
            }
            flush()
            run = (record, record.startedAt, record.endedAt)
        }
        flush()
        return merged
    }

    static func block(for record: ActivityRecord) -> TimelineBlock {
        TimelineBlock(
            id: "activity-\(record.id)",
            kind: record.isIdle ? .idle : .activity,
            title: record.isIdle ? "Away" : record.appName,
            subtitle: record.windowTitle ?? record.url,
            category: record.isIdle ? "Away" : ActivityRecord.currentCategory(for: record),
            start: record.startedAt,
            end: record.endedAt,
            focusRating: nil
        )
    }
}
