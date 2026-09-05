import SwiftData
import SwiftUI

/// The day timeline: an hour gutter, a grid, a narrow rail of passively tracked
/// activity, and a wide lane of sessions and hand-made entries.
struct DayTimelineView: View {

    let day: Date
    @Binding var hourHeight: CGFloat

    @Query private var sessions: [WorkSession]
    @Query private var entries: [TimeEntry]
    @Query private var activity: [ActivityRecord]

    @State private var selection: TimelineBlock?

    private static let gutterWidth: CGFloat = 52
    private static let railWidth: CGFloat = 14
    private static let railGap: CGFloat = 10

    init(day: Date, hourHeight: Binding<CGFloat>) {
        self.day = day
        self._hourHeight = hourHeight

        // Queries are bounded to the day so the view never loads the whole
        // history to draw twenty-four hours of it.
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _sessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
        _entries = Query(filter: #Predicate<TimeEntry> { $0.startedAt >= start && $0.startedAt < end },
                         sort: \.startedAt)
        _activity = Query(filter: #Predicate<ActivityRecord> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
    }

    private var geometry: TimelineGeometry {
        TimelineGeometry(dayStart: Calendar.current.startOfDay(for: day), hourHeight: hourHeight)
    }

    private var blocks: [TimelineBlock] {
        let now = Date.now
        return sessions.flatMap { TimelineBlock.blocks(for: $0, now: now) }
            + entries.map(TimelineBlock.block(for:))
            + activity.map(TimelineBlock.block(for:))
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    HourGutter(geometry: geometry, width: Self.gutterWidth)
                    track
                }
                .frame(height: geometry.totalHeight, alignment: .top)
            }
            .task(id: day) { await scrollToRelevantHour(using: proxy) }
        }
        .background(Theme.canvas)
        .popover(item: $selection) { block in
            TimelineBlockDetail(block: block)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let laneWidth = max(40, proxy.size.width - Self.railWidth - Self.railGap)
            ZStack(alignment: .topLeading) {
                TimelineGrid(geometry: geometry)

                // Passively tracked usage: a continuous ribbon, no labels. The
                // tracker only ever has one frontmost app, so these never
                // overlap and need no lane assignment.
                ForEach(ribbonBlocks) { block in
                    let extent = geometry.extent(for: block)
                    RibbonBlockView(block: block)
                        .frame(width: Self.railWidth, height: extent.height)
                        .offset(y: extent.y)
                        .onTapGesture { selection = block }
                }

                // Sessions and entries: full cards, lane-packed where they
                // genuinely overlap each other.
                ForEach(TimelineLayout.lanes(for: cardBlocks)) { laid in
                    let extent = geometry.extent(for: laid.block, minimumHeight: 14)
                    let width = laneWidth / CGFloat(laid.laneCount)
                    CardBlockView(block: laid.block, height: extent.height)
                        .frame(width: max(24, width - 3), height: extent.height, alignment: .topLeading)
                        .offset(x: Self.railWidth + Self.railGap + width * CGFloat(laid.lane),
                                y: extent.y)
                        .onTapGesture { selection = laid.block }
                }

                if isToday {
                    NowIndicator(geometry: geometry)
                }
            }
        }
    }

    private var ribbonBlocks: [TimelineBlock] { blocks.filter(\.kind.isRibbon) }
    private var cardBlocks: [TimelineBlock] { blocks.filter { !$0.kind.isRibbon } }

    /// Opens on the part of the day worth looking at: an hour before now for
    /// today, or the first thing that happened on a past day.
    private func scrollToRelevantHour(using proxy: ScrollViewProxy) async {
        // A scroll issued before the first layout pass is silently dropped.
        try? await Task.sleep(for: .milliseconds(60))
        let calendar = Calendar.current
        let anchorDate: Date? = isToday
            ? .now
            : blocks.map(\.start).min()
        guard let anchorDate else { return }
        let hour = max(0, calendar.component(.hour, from: anchorDate) - 1)
        withAnimation(.none) { proxy.scrollTo(HourAnchor(hour: hour), anchor: .top) }
    }
}

/// Identifies an hour row so `ScrollViewProxy` can jump to it.
private struct HourAnchor: Hashable { let hour: Int }

// MARK: - Gutter and grid

private struct HourGutter: View {
    let geometry: TimelineGeometry
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(0..<geometry.hourCount, id: \.self) { hour in
                Text(Format.hourLabel(hour))
                    .font(Theme.Font.gutter)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .padding(.trailing, Theme.Space.s)
                    // Nudged up by half a line so the label reads as sitting on
                    // its gridline rather than below it.
                    .offset(y: CGFloat(hour) * geometry.hourHeight - 6)
                    .id(HourAnchor(hour: hour))
            }
        }
        .frame(width: width, height: geometry.totalHeight, alignment: .topTrailing)
    }
}

private struct TimelineGrid: View {
    let geometry: TimelineGeometry

    /// Half-hour rules stop earning their keep once the rows get short.
    private var showsHalfHours: Bool { geometry.hourHeight >= 44 }

    var body: some View {
        // One Canvas rather than ~48 Divider views: the grid is decoration and
        // should cost one draw call, not fifty layout nodes.
        Canvas { context, size in
            for hour in 0...geometry.hourCount {
                let y = CGFloat(hour) * geometry.hourHeight
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(Theme.hairline),
                    lineWidth: 0.5
                )
                guard showsHalfHours, hour < geometry.hourCount else { continue }
                let half = y + geometry.hourHeight / 2
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: half)); $0.addLine(to: CGPoint(x: size.width, y: half)) },
                    with: .color(Theme.hairlineFaint),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Now indicator

private struct NowIndicator: View {
    let geometry: TimelineGeometry

    var body: some View {
        // Isolated in its own TimelineView so the per-minute tick redraws a
        // hairline and a dot, never the day's blocks.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.now)
                    .frame(height: 1)
                Circle()
                    .fill(Theme.now)
                    .frame(width: 6, height: 6)
                    .offset(x: -2)
            }
            .offset(y: geometry.y(for: context.date))
            .allowsHitTesting(false)
        }
    }
}
