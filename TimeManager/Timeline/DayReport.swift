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
        self.focusedTime = sessionBlocks.reduce(0) { $0 + $1.duration }
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
            totals[record.categoryName ?? record.appName, default: 0] += record.duration
        }
        let grand = totals.values.reduce(0, +)
        self.categories = totals
            .map { CategoryTotal(name: $0.key, duration: $0.value, fraction: grand > 0 ? $0.value / grand : 0) }
            .sorted { $0.duration > $1.duration }
    }

    /// When the user last stopped working, used for the HUD's "time since last
    /// break". Returns the end of the most recent idle span.
    static func lastBreakEnd(in activity: [ActivityRecord]) -> Date? {
        activity.filter(\.isIdle).map(\.endedAt).max()
    }
}
