import Foundation
import SwiftUI

/// Maps between wall-clock time and vertical offsets in the day timeline.
struct TimelineGeometry {
    /// Midnight of the day being displayed.
    let dayStart: Date
    /// Points per hour. Drives the whole timeline's scale.
    let hourHeight: CGFloat

    /// Actual length of this day in hours. Not always 24: the days a DST
    /// transition lands on are 23 or 25 hours long, and hard-coding 24 would
    /// slide every block on those days by an hour.
    var hourCount: Int {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 24 }
        return Int((next.timeIntervalSince(dayStart) / 3600).rounded())
    }

    var totalHeight: CGFloat { CGFloat(hourCount) * hourHeight }

    /// Vertical offset for a point in time, clamped to the day.
    func y(for date: Date) -> CGFloat {
        let hours = date.timeIntervalSince(dayStart) / 3600
        return min(max(0, CGFloat(hours) * hourHeight), totalHeight)
    }

    /// Inverse of `y(for:)` — used to place a new entry where the user clicks.
    func date(for y: CGFloat) -> Date {
        let clamped = min(max(0, y), totalHeight)
        return dayStart.addingTimeInterval(TimeInterval(clamped / hourHeight) * 3600)
    }

    /// Vertical extent of a block, clipped to the visible day and given a floor
    /// so a very short span stays visible and clickable.
    func extent(for block: TimelineBlock, minimumHeight: CGFloat = 3) -> (y: CGFloat, height: CGFloat) {
        let top = y(for: block.start)
        let bottom = y(for: block.end)
        return (top, max(minimumHeight, bottom - top))
    }
}

/// A block together with the horizontal slot it should occupy.
struct LaidOutBlock: Identifiable {
    let block: TimelineBlock
    /// Zero-based column within its overlapping cluster.
    let lane: Int
    /// How many columns that cluster needs.
    let laneCount: Int

    var id: String { block.id }
}

enum TimelineLayout {

    /// Packs overlapping blocks into side-by-side columns, the way a calendar
    /// week view does.
    ///
    /// Blocks are first split into clusters of transitively overlapping spans,
    /// then lane-assigned greedily within each cluster. Clustering matters: it
    /// keeps the column count local, so one busy hour with four overlapping
    /// sessions doesn't squeeze every other block in the day to a quarter width.
    static func lanes(for blocks: [TimelineBlock]) -> [LaidOutBlock] {
        let sorted = blocks.sorted {
            $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start
        }

        var result: [LaidOutBlock] = []
        var cluster: [(block: TimelineBlock, lane: Int)] = []
        // End time of the last block in each lane of the current cluster.
        var laneEnds: [Date] = []

        func flush() {
            guard !cluster.isEmpty else { return }
            let count = laneEnds.count
            result.append(contentsOf: cluster.map {
                LaidOutBlock(block: $0.block, lane: $0.lane, laneCount: count)
            })
            cluster.removeAll()
            laneEnds.removeAll()
        }

        for block in sorted {
            // A block starting at or after every open lane's end begins a new
            // cluster — nothing before it can overlap anything after it.
            if let latest = laneEnds.max(), block.start >= latest {
                flush()
            }
            let lane = laneEnds.firstIndex { $0 <= block.start } ?? laneEnds.count
            if lane < laneEnds.count {
                laneEnds[lane] = block.end
            } else {
                laneEnds.append(block.end)
            }
            cluster.append((block, lane))
        }
        flush()
        return result
    }
}
