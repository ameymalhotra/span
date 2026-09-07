import Foundation
import SwiftUI

/// A single category's share of a day.
struct CategoryTotal: Identifiable, Hashable {
    let name: String
    let duration: TimeInterval
    /// Share of the day's tracked time, 0...1.
    let fraction: Double

    var id: String { name }
    var color: Color { CategoryPalette.color(for: name) }
}

/// Everything the day views need, derived once from the day's raw records.
///
/// The views used to recompute their own `reduce`s inline, which meant the
/// timeline, the summary and the menu bar could each disagree about the day's
/// total. Deriving them together here keeps one answer.
struct DayReport {

    let day: Date
    let blocks: [TimelineBlock]

    /// Time inside focus sessions, pauses excluded.
    let focusedTime: TimeInterval
    /// Time the tracker saw at the keyboard, idle excluded.
    let trackedTime: TimeInterval
    /// What the user themselves said was real work, summed over reflected
    /// sessions. Deliberately separate from `focusedTime`: the gap between the
    /// two is the point of the reflection feature.
    let honestWorkTime: TimeInterval
    /// Sessions the user has reviewed, over sessions finished.
    let reflectedCount: Int
    let completedCount: Int
    let distractions: Int
    let categories: [CategoryTotal]

    /// Fraction of a 24-hour day that was tracked, for the HUD's "percent of day".
    var dayFraction: Double { trackedTime / (24 * 3600) }

    static let empty = DayReport(
        day: .now, blocks: [], focusedTime: 0, trackedTime: 0, honestWorkTime: 0,
        reflectedCount: 0, completedCount: 0, distractions: 0, categories: []
    )

    init(
        day: Date,
        blocks: [TimelineBlock],
        focusedTime: TimeInterval,
        trackedTime: TimeInterval,
        honestWorkTime: TimeInterval,
        reflectedCount: Int,
        completedCount: Int,
        distractions: Int,
        categories: [CategoryTotal]
    ) {
        self.day = day
        self.blocks = blocks
        self.focusedTime = focusedTime
        self.trackedTime = trackedTime
        self.honestWorkTime = honestWorkTime
        self.reflectedCount = reflectedCount
        self.completedCount = completedCount
        self.distractions = distractions
        self.categories = categories
    }

    /// Builds the report for `day` from the records that touch it.
    init(
        day: Date,
        sessions: [WorkSession],
        entries: [TimeEntry],
        activity: [ActivityRecord],
        now: Date = .now
    ) {
        let sessionBlocks = sessions.flatMap { TimelineBlock.blocks(for: $0, now: now) }
        let entryBlocks = entries.map(TimelineBlock.block(for:))
        let activityBlocks = activity.map(TimelineBlock.block(for:))

        self.day = day
        self.blocks = sessionBlocks + entryBlocks + activityBlocks
        self.focusedTime = sessions.reduce(0) { $0 + $1.elapsed(at: now) }
        self.trackedTime = activity.filter { !$0.isIdle }.reduce(0) { $0 + $1.duration }

        let completed = sessions.filter { $0.status == .completed }
        self.completedCount = completed.count
        self.reflectedCount = completed.filter(\.isReflected).count
        self.honestWorkTime = completed.reduce(0) { $0 + TimeInterval(($1.honestWorkMinutes ?? 0) * 60) }
        self.distractions = completed.reduce(0) { $0 + ($1.distractions ?? 0) }

        // Category totals span every source, so a day reads consistently whether
        // its time came from a session, a hand-made entry or the tracker.
        var totals: [String: TimeInterval] = [:]
        for block in sessionBlocks + entryBlocks {
            totals[block.category ?? "Uncategorised", default: 0] += block.duration
        }
        for record in activity where !record.isIdle {
            totals[ActivityRecord.currentCategory(for: record), default: 0] += record.duration
        }
        let grand = totals.values.reduce(0, +)
        self.categories = totals
            .map { CategoryTotal(name: $0.key, duration: $0.value, fraction: grand > 0 ? $0.value / grand : 0) }
            .sorted { $0.duration > $1.duration }
    }

    /// How much reviewed time was clocked, and how much of it the user called
    /// real work.
    ///
    /// Only reviewed sessions are counted. An unreviewed session has no answer,
    /// and treating its time as "didn't feel real" would be inventing one.
    ///
    /// `honest` is capped at `clocked` so the pair can be drawn as a whole and
    /// its part. Read as two independent series they had nothing holding them
    /// in order, and the part could be plotted taller than the whole it came
    /// out of.
    static func honestySplit(of sessions: [WorkSession]) -> (clocked: TimeInterval, honest: TimeInterval) {
        let reviewed = sessions.filter(\.isReflected)
        let clocked = reviewed.reduce(0) { $0 + $1.elapsed() }
        let honest = reviewed.reduce(0) { $0 + TimeInterval(($1.honestWorkMinutes ?? 0) * 60) }
        return (clocked, min(honest, clocked))
    }

    /// When the user last resumed after a break, for "time since last break".
    ///
    /// Recorded idle spans are not the whole story: while the app is closed or
    /// tracking is paused nothing is written at all, so a night's sleep leaves
    /// no idle record and the counter claims you have been at it for thirteen
    /// hours. A gap in the recording is therefore treated as a break too — if
    /// nothing was tracked for longer than the idle threshold, you were not
    /// working through it.
    static func lastBreakEnd(in activity: [ActivityRecord], threshold: TimeInterval) -> Date? {
        let sorted = activity.sorted { $0.startedAt < $1.startedAt }
        var lastBreakEnd: Date?
        var previousEnd: Date?

        for record in sorted {
            if let previous = previousEnd,
               record.startedAt.timeIntervalSince(previous) >= threshold {
                lastBreakEnd = record.startedAt
            }
            if record.isIdle {
                lastBreakEnd = record.endedAt
            }
            previousEnd = max(previousEnd ?? record.endedAt, record.endedAt)
        }

        // A trailing gap counts too: tracking may have stopped an hour ago.
        if let previous = previousEnd,
           Date.now.timeIntervalSince(previous) >= threshold {
            return nil
        }
        return lastBreakEnd
    }
}
