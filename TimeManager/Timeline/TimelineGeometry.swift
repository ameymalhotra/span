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

    /// The wall-clock hour shown at row `index`.
    ///
    /// Not simply `index`: rows are elapsed hours from midnight, and on a DST
    /// day those stop matching the clock at the transition. On a 25-hour day
    /// row 14 is 1 PM, not 2 PM — labelling it by index put every block after
    /// the change an hour away from its own label.
    func hour(atRow index: Int) -> Int {
        Calendar.current.component(.hour, from: date(for: CGFloat(index) * hourHeight))
    }

    /// The row a moment falls in — the inverse of `hour(atRow:)`, for scrolling
    /// to a time of day.
    func row(for date: Date) -> Int {
        Int(date.timeIntervalSince(dayStart) / 3600)
    }

    /// Rounds a time to the nearest `minutes`, so dragged blocks land on tidy
    /// boundaries the way calendar events do rather than on 10:37.
    func snapped(_ date: Date, minutes: Int = 5) -> Date {
        let step = TimeInterval(minutes * 60)
        let offset = date.timeIntervalSince(dayStart)
        return dayStart.addingTimeInterval((offset / step).rounded() * step)
    }

    /// Vertical extent of a block, clipped to the visible day and given a floor
    /// so a very short span stays visible and clickable.
    func extent(for block: TimelineBlock, minimumHeight: CGFloat = 3) -> (y: CGFloat, height: CGFloat) {
        let top = y(for: block.start)
        let bottom = y(for: block.end)
        return (top, max(minimumHeight, bottom - top))
    }

    /// Where a panel anchored beside a block should sit so that all of it stays
    /// inside the day.
    ///
    /// The timeline's scroll content is exactly `totalHeight` tall, so a panel
    /// running past the bottom is cut off rather than scrolled to — which is
    /// what happened to every block late in the evening while this was clamped
    /// against an assumed height instead of the panel's real one.
    func panelTop(anchoredAt anchor: CGFloat, height: CGFloat, inset: CGFloat = 8) -> CGFloat {
        min(max(0, anchor - inset), max(0, totalHeight - height - inset))
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

/// A block with its final on-screen rectangle.
struct PlacedBlock: Identifiable {
    let block: TimelineBlock
    let lane: Int
    let laneCount: Int
    let y: CGFloat
    let height: CGFloat

    var id: String { block.id }
}

enum TimelineLayout {

    /// Places blocks with a legible minimum height.
    ///
    /// A minimum height alone is not safe: two five-minute blocks six minutes
    /// apart do not overlap in time, but at 24pt each they collide on screen —
    /// which renders as two cards drawn over one another. Within each lane the
    /// blocks are therefore cascaded: a block that would start above the
    /// previous one's bottom is pushed down. Dense clusters drift slightly from
    /// true time, which is the trade calendars make too, and the alternative is
    /// illegible.
    static func place(
        _ blocks: [TimelineBlock],
        in geometry: TimelineGeometry,
        minimumHeight: CGFloat,
        spacing: CGFloat = 2
    ) -> [PlacedBlock] {
        let laid = lanes(for: blocks)
        var cursorByLane: [Int: CGFloat] = [:]
        var placed: [PlacedBlock] = []

        for item in laid.sorted(by: { $0.block.start < $1.block.start }) {
            let top = geometry.y(for: item.block.start)
            let natural = geometry.y(for: item.block.end) - top
            let height = max(minimumHeight, natural)
            let cursor = cursorByLane[item.lane] ?? -.greatestFiniteMagnitude
            let y = max(top, cursor)
            cursorByLane[item.lane] = y + height + spacing
            placed.append(PlacedBlock(block: item.block, lane: item.lane,
                                      laneCount: item.laneCount, y: y, height: height))
        }
        return placed
    }


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
