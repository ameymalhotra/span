import SwiftData
import SwiftUI

/// The day timeline: an hour gutter, a grid, a narrow rail of passively tracked
/// activity, and a wide lane of sessions and hand-made blocks.
///
/// The lane is directly editable the way a calendar is: drag empty space to
/// create a block, drag a block to move it, drag its edges to resize.
struct DayTimelineView: View {

    let day: Date
    @Binding var hourHeight: CGFloat

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model

    @Query private var sessions: [WorkSession]
    @Query private var entries: [TimeEntry]
    @Query private var activity: [ActivityRecord]

    @State private var selection: TimelineBlock?
    @State private var editingEntry: TimeEntry?
    @State private var draft: DraftRange?
    @State private var dragOrigin: (start: Date, end: Date)?
    @State private var hoveredRail: TimelineBlock?

    private static let gutterWidth: CGFloat = 52
    /// Wide enough to read as a continuous band of the day rather than a line
    /// of slivers; short app switches are only a few points tall.
    private static let railWidth: CGFloat = 20
    private static let railGap: CGFloat = 12
    private static let handleHeight: CGFloat = 6

    /// A block being dragged out but not yet committed.
    private struct DraftRange {
        var anchor: Date
        var current: Date
        var lower: Date { min(anchor, current) }
        var upper: Date { max(anchor, current) }
    }

    init(day: Date, hourHeight: Binding<CGFloat>) {
        self.day = day
        self._hourHeight = hourHeight

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
            + TimelineBlock.mergedActivityBlocks(activity)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var knownCategories: [String] {
        var seen: [String] = []
        for name in sessions.map(\.category) + entries.map(\.category) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.append(trimmed)
        }
        return Array(seen.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineLegend(entries: legendEntries)
            Divider()
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
        }
        .background(Theme.canvas)
        .onChange(of: model.pendingBlockEdit) { _, entry in
            guard let entry else { return }
            editingEntry = entry
            model.pendingBlockEdit = nil
        }
        .overlay(alignment: .bottom) {
            if blocks.isEmpty { emptyHint }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let laneWidth = max(40, proxy.size.width - Self.railWidth - Self.railGap)
            let laneX = Self.railWidth + Self.railGap
            ZStack(alignment: .topLeading) {
                // Laid-out rows, one per hour, purely as scroll anchors. Offset
                // views do not move in layout, so they cannot be scrolled to.
                VStack(spacing: 0) {
                    ForEach(0..<geometry.hourCount, id: \.self) { hour in
                        Color.clear
                            .frame(height: geometry.hourHeight)
                            .id(HourAnchor(hour: hour))
                    }
                }

                TimelineGrid(geometry: geometry)

                creationLayer(laneX: laneX, laneWidth: laneWidth)

                ActivityRail(blocks: ribbonBlocks, geometry: geometry)
                    .frame(width: Self.railWidth, height: geometry.totalHeight)

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: Self.railWidth, height: geometry.totalHeight)
                    .onContinuousHover { phase in
                        guard case .active(let point) = phase else {
                            hoveredRail = nil
                            return
                        }
                        let moment = geometry.date(for: point.y)
                        hoveredRail = ribbonBlocks.first { $0.start <= moment && moment <= $0.end }
                    }

                if let hoveredRail {
                    railReadout(hoveredRail)
                        .offset(x: Self.railWidth + 6,
                                y: max(0, geometry.y(for: hoveredRail.start) - 4))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                ForEach(TimelineLayout.place(cardBlocks, in: geometry, minimumHeight: 26)) { placed in
                    laneCard(placed, laneX: laneX, laneWidth: laneWidth)
                }

                if let draft {
                    draftGhost(draft, laneX: laneX, laneWidth: laneWidth)
                }

                if isToday {
                    NowIndicator(geometry: geometry)
                }
            }
        }
    }

    // MARK: - Creating

    /// Empty lane space. Dragging here sweeps out a block the way dragging in a
    /// calendar does; the result is committed on release and opened for naming.
    private func creationLayer(laneX: CGFloat, laneWidth: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: laneWidth, height: geometry.totalHeight)
            .offset(x: laneX)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let anchor = geometry.snapped(geometry.date(for: value.startLocation.y))
                        let current = geometry.snapped(geometry.date(for: value.location.y))
                        draft = DraftRange(anchor: anchor, current: current)
                    }
                    .onEnded { _ in
                        guard let draft else { return }
                        self.draft = nil
                        // A flick that collapses to nothing still means "a block
                        // here", so it gets a sensible default length.
                        let lower = draft.lower
                        let upper = draft.upper > draft.lower
                            ? draft.upper
                            : draft.lower.addingTimeInterval(30 * 60)
                        create(from: lower, to: upper)
                    }
            )
    }

    private func create(from start: Date, to end: Date) {
        let entry = TimeEntry(title: "", category: "", startedAt: start, endedAt: end)
        context.insert(entry)
        try? context.save()
        editingEntry = entry
    }

    /// Adds a block at the current time — the keyboard/toolbar route for people
    /// who would rather not drag.
    func addBlockAtNow() {
        let start = geometry.snapped(.now)
        create(from: start, to: start.addingTimeInterval(30 * 60))
    }

    private func draftGhost(_ draft: DraftRange, laneX: CGFloat, laneWidth: CGFloat) -> some View {
        let top = geometry.y(for: draft.lower)
        let height = max(4, geometry.y(for: draft.upper) - top)
        return RoundedRectangle(cornerRadius: Theme.Radius.block)
            .fill(Theme.accent.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.block)
                    .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text("\(Format.timeOfDay(draft.lower)) – \(Format.timeOfDay(draft.upper))")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .frame(width: laneWidth - 3, height: height)
            .offset(x: laneX, y: top)
            .allowsHitTesting(false)
    }

    // MARK: - Cards

    @ViewBuilder
    private func laneCard(_ placed: PlacedBlock, laneX: CGFloat, laneWidth: CGFloat) -> some View {
        let width = laneWidth / CGFloat(placed.laneCount)
        let entry = entry(for: placed.block)

        CardBlockView(block: placed.block, height: placed.height)
            .frame(width: max(24, width - 3), height: placed.height, alignment: .topLeading)
            .overlay(alignment: .top) { resizeHandle(entry, edge: .top) }
            .overlay(alignment: .bottom) { resizeHandle(entry, edge: .bottom) }
            .offset(x: laneX + width * CGFloat(placed.lane), y: placed.y)
            .onTapGesture {
                if let entry { editingEntry = entry } else { selection = placed.block }
            }
            .gesture(moveGesture(for: entry))
            // Anchored to the block rather than to the timeline, so the detail
            // appears beside what was clicked and moves with it when scrolling.
            .popover(isPresented: detailBinding(for: placed.block), arrowEdge: .trailing) {
                TimelineBlockDetail(block: placed.block)
            }
            .popover(isPresented: editorBinding(for: entry), arrowEdge: .trailing) {
                if let entry { TimeEntryEditor(entry: entry) }
            }
    }

    private func detailBinding(for block: TimelineBlock) -> Binding<Bool> {
        Binding(
            get: { selection?.id == block.id },
            set: { if !$0 { selection = nil } }
        )
    }

    private func editorBinding(for entry: TimeEntry?) -> Binding<Bool> {
        Binding(
            get: { entry != nil && editingEntry?.id == entry?.id },
            set: { if !$0 { editingEntry = nil } }
        )
    }

    /// A floating label for whatever the pointer is over in the rail.
    private func railReadout(_ block: TimelineBlock) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(Theme.Font.blockTitle)
                .foregroundStyle(Theme.label)
            Text("\(Format.timeOfDay(block.start)) – \(Format.timeOfDay(block.end)) · \(Format.compact(block.duration))")
                .font(Theme.Font.micro)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryLabel)
            if let subtitle = block.subtitle {
                Text(subtitle)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.block))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .frame(maxWidth: 240, alignment: .leading)
        .fixedSize()
    }

    /// What the rail's colours mean, so the stripes do not have to be
    /// interrogated one by one.
    private var legendEntries: [CategoryTotal] {
        var totals: [String: TimeInterval] = [:]
        for block in ribbonBlocks where block.kind == .activity {
            totals[block.category ?? block.title, default: 0] += block.duration
        }
        let grand = totals.values.reduce(0, +)
        return totals
            .map { CategoryTotal(name: $0.key, duration: $0.value,
                                 fraction: grand > 0 ? $0.value / grand : 0) }
            .sorted { $0.duration > $1.duration }
    }

    private enum Edge { case top, bottom }

    @ViewBuilder
    private func resizeHandle(_ entry: TimeEntry?, edge: Edge) -> some View {
        if let entry {
            Color.clear
                .contentShape(Rectangle())
                .frame(height: Self.handleHeight)
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragOrigin == nil {
                                dragOrigin = (entry.startedAt, entry.endedAt)
                            }
                            guard let origin = dragOrigin else { return }
                            let delta = TimeInterval(value.translation.height / hourHeight) * 3600
                            switch edge {
                            case .top:
                                let moved = geometry.snapped(origin.start.addingTimeInterval(delta))
                                entry.startedAt = min(moved, origin.end.addingTimeInterval(-5 * 60))
                            case .bottom:
                                let moved = geometry.snapped(origin.end.addingTimeInterval(delta))
                                entry.endedAt = max(moved, origin.start.addingTimeInterval(5 * 60))
                            }
                        }
                        .onEnded { _ in
                            dragOrigin = nil
                            try? context.save()
                        }
                )
        }
    }

    private func moveGesture(for entry: TimeEntry?) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard let entry else { return }
                if dragOrigin == nil { dragOrigin = (entry.startedAt, entry.endedAt) }
                guard let origin = dragOrigin else { return }
                let delta = TimeInterval(value.translation.height / hourHeight) * 3600
                let length = origin.end.timeIntervalSince(origin.start)
                let moved = geometry.snapped(origin.start.addingTimeInterval(delta))
                entry.startedAt = moved
                entry.endedAt = moved.addingTimeInterval(length)
            }
            .onEnded { _ in
                guard entry != nil else { return }
                dragOrigin = nil
                try? context.save()
            }
    }

    private func entry(for block: TimelineBlock) -> TimeEntry? {
        guard block.kind == .entry else { return nil }
        return entries.first { "entry-\($0.id)" == block.id }
    }

    /// Shown only on a genuinely empty day — the one place the drag gesture is
    /// worth spelling out, since nothing on screen implies it.
    private var emptyHint: some View {
        Text("Drag anywhere on the timeline to add a block")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.tertiaryLabel)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.surface, in: Capsule())
            .padding(.bottom, Theme.Space.xl)
            .allowsHitTesting(false)
    }

    private var ribbonBlocks: [TimelineBlock] { blocks.filter(\.kind.isRibbon) }
    private var cardBlocks: [TimelineBlock] { blocks.filter { !$0.kind.isRibbon } }

    /// Opens on the part of the day worth looking at: an hour before now for
    /// today, or the first thing that happened on a past day.
    private func scrollToRelevantHour(using proxy: ScrollViewProxy) async {
        // A scroll issued before the first layout pass is silently dropped.
        try? await Task.sleep(for: .milliseconds(80))
        let calendar = Calendar.current
        let anchorDate: Date? = isToday ? .now : blocks.map(\.start).min()
        guard let anchorDate else { return }
        let hour = max(0, calendar.component(.hour, from: anchorDate) - 1)
        proxy.scrollTo(HourAnchor(hour: hour), anchor: .top)
    }
}

/// Identifies an hour row so `ScrollViewProxy` can jump to it.
struct HourAnchor: Hashable { let hour: Int }

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
            }
        }
        .frame(width: width, height: geometry.totalHeight, alignment: .topTrailing)
    }
}

private struct TimelineGrid: View {
    let geometry: TimelineGeometry

    /// Half-hour rules stop earning their keep once the rows get short.
    private var showsHalfHours: Bool { geometry.hourHeight >= 90 }

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

/// Names the colours in the activity rail, with how long each took.
private struct TimelineLegend: View {
    let entries: [CategoryTotal]
    private static let shown = 5

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("Nothing tracked yet today")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.m) {
                        ForEach(entries.prefix(Self.shown)) { entry in
                            HStack(spacing: Theme.Space.xs) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(entry.color)
                                    .frame(width: 8, height: 8)
                                Text(entry.name)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                                Text(Format.compact(entry.duration))
                                    .font(Theme.Font.caption.monospacedDigit())
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                        if entries.count > Self.shown {
                            Text("+\(entries.count - Self.shown) more")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.tertiaryLabel)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 30)
    }
}

/// Passively tracked time, painted as one continuous band.
///
/// Drawn as separate rounded chips the rail became a column of disconnected
/// pills — the tracker writes a record per app or title change, so most are only
/// a few points tall. A contiguous band reads as the shape of the day instead,
/// and short stretches are legible as stripes within it rather than as slivers
/// floating on their own.
private struct ActivityRail: View {
    let blocks: [TimelineBlock]
    let geometry: TimelineGeometry

    var body: some View {
        Canvas { context, size in
            for block in blocks {
                let top = geometry.y(for: block.start)
                let height = max(1, geometry.y(for: block.end) - top)
                let rect = CGRect(x: 0, y: top, width: size.width, height: height)
                let colour: Color = block.kind == .idle
                    ? Theme.tertiaryLabel.opacity(0.28)
                    : block.color.opacity(0.9)
                context.fill(Path(rect), with: .color(colour))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
