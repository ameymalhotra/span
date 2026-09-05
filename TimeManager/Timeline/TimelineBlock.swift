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
        return session.segments
            .sorted { $0.startedAt < $1.startedAt }
            .enumerated()
            .map { index, segment in
                TimelineBlock(
                    id: "session-\(session.id)-\(index)",
                    kind: .session,
                    title: session.title,
                    subtitle: category,
                    category: category,
                    start: segment.startedAt,
                    end: segment.endedAt ?? now,
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

    static func block(for record: ActivityRecord) -> TimelineBlock {
        TimelineBlock(
            id: "activity-\(record.id)",
            kind: record.isIdle ? .idle : .activity,
            title: record.isIdle ? "Away" : record.appName,
            subtitle: record.windowTitle ?? record.url,
            category: record.categoryName ?? record.appName,
            start: record.startedAt,
            end: record.endedAt,
            focusRating: nil
        )
    }
}
