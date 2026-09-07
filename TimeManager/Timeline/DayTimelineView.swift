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
    @State private var editingSession: WorkSession?
    @State private var draft: DraftRange?
    @State private var dragOrigin: (start: Date, end: Date)?
    @State private var hoveredRail: TimelineBlock?
    @State private var inspectorY: CGFloat = 0
    /// The panel's measured height, so it can be kept inside the track. A
    /// guessed constant is what used to push half of it off the bottom.
    @State private var inspectorHeight: CGFloat = 260
    @State private var hoveredCard: String?
    @AppStorage("timelineGrouping") private var groupingRaw = TimelineGrouping.category.rawValue

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
        // Establishes a dependency on the palette, which is otherwise a static
        // lookup SwiftUI cannot see changing.
        _ = model.paletteGeneration
        let now = Date.now
        return sessions.flatMap { TimelineBlock.blocks(for: $0, now: now) }
            + entries.map(TimelineBlock.block(for:))
            + TimelineBlock.mergedActivityBlocks(activity, grouping: grouping)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var grouping: TimelineGrouping {
        TimelineGrouping(rawValue: groupingRaw) ?? .category
    }

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
            TimelineLegend(entries: legendEntries, grouping: $groupingRaw)
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

                if editingEntry != nil || editingSession != nil || selection != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: proxy.size.width, height: geometry.totalHeight)
                        .onTapGesture {
                            editingEntry = nil
                            editingSession = nil
                            selection = nil
                        }
                        .zIndex(9)
                }

                inspector(laneX: laneX, laneWidth: laneWidth, trackWidth: proxy.size.width)
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
        inspectorY = geometry.y(for: start)
        selection = nil
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

        let target = resizable(for: placed.block)
        let isHovered = hoveredCard == placed.block.id

        CardBlockView(block: placed.block, height: placed.height)
            .frame(width: max(24, width - 3), height: placed.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onHover { hoveredCard = $0 ? placed.block.id : nil }
            .overlay { moveArea(placed, entry: entry) }
            .overlay(alignment: .top) { resizeHandle(target, isHovered: isHovered, edge: .top) }
            .overlay(alignment: .bottom) { resizeHandle(target, isHovered: isHovered, edge: .bottom) }
            .accessibilityIdentifier("timeline.block.\(placed.block.id)")
            .offset(x: laneX + width * CGFloat(placed.lane), y: placed.y)
    }

    /// The part of a card that opens it and drags it around: everything except
    /// the resize strips at either end.
    private func moveArea(_ placed: PlacedBlock, entry: TimeEntry?) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .padding(.vertical, Self.handleHeight)
            .accessibilityIdentifier("timeline.card.\(placed.block.id)")
            .onTapGesture {
                inspectorY = placed.y
                selection = nil
                editingEntry = nil
                editingSession = nil
                if let entry {
                    editingEntry = entry
                } else if let session = session(for: placed.block) {
                    editingSession = session
                } else {
                    selection = placed.block
                }
            }
            .gesture(moveGesture(for: entry))
    }

    /// The detail or editor, drawn in the timeline beside the block it belongs
    /// to.
    ///
    /// This was a popover, which is the obvious tool but an unreliable one
    /// here: nested in a ScrollView inside a GeometryReader it anchored to the
    /// pane rather than the block, and a view can only present one at a time,
    /// so the detail and the editor cancelled each other out. An ordinary view
    /// positioned in the same coordinate space as the blocks has neither
    /// problem.
    @ViewBuilder
    private func inspector(laneX: CGFloat, laneWidth: CGFloat, trackWidth: CGFloat) -> some View {
        if editingEntry != nil || editingSession != nil || selection != nil {
            let panelWidth: CGFloat = 300
            // Sits beside the lane where there is room, and tucks inside the
            // track when the pane is narrow.
            let x = min(max(laneX + Theme.Space.s, 0), max(0, trackWidth - panelWidth - 4))
            // Clamped against the panel's own measured height rather than the
            // 260 points once assumed here.
            let y = geometry.panelTop(anchoredAt: inspectorY, height: inspectorHeight)

            Group {
                if let entry = editingEntry {
                    TimeEntryEditor(entry: entry) { editingEntry = nil }
                } else if let session = editingSession {
                    SessionEditor(session: session) { editingSession = nil }
                } else if let block = selection {
                    TimelineBlockDetail(block: block) { selection = nil }
                }
            }
            .frame(width: panelWidth, alignment: .topLeading)
            .background {
                GeometryReader { panel in
                    Color.clear
                        .onChange(of: panel.size.height, initial: true) { _, height in
                            guard height > 0 else { return }
                            inspectorHeight = height
                        }
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
            .offset(x: x, y: y)
            .zIndex(10)
        }
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

    /// What the rail's colours mean, and what went into each one.
    ///
    /// Built from the records rather than the merged blocks, so it knows which
    /// apps make up a category and can offer to re-file them.
    private var legendEntries: [LegendEntry] {
        var groups: [String: (total: TimeInterval, apps: [String: (name: String, total: TimeInterval)])] = [:]
        for record in activity where !record.isIdle {
            let key = grouping == .app
                ? record.appName
                : AppCategorizer.category(forBundleIdentifier: record.bundleIdentifier,
                                          appName: record.appName)
            var group = groups[key] ?? (0, [:])
            group.total += record.duration
            let bundle = record.bundleIdentifier ?? record.appName
            var app = group.apps[bundle] ?? (record.appName, 0)
            app.total += record.duration
            group.apps[bundle] = app
            groups[key] = group
        }
        let grand = groups.values.reduce(0) { $0 + $1.total }
        return groups
            .map { name, value in
                LegendEntry(
                    name: name,
                    duration: value.total,
                    fraction: grand > 0 ? value.total / grand : 0,
                    apps: value.apps
                        .map { LegendEntry.AppShare(bundleIdentifier: $0.key,
                                                    name: $0.value.name,
                                                    duration: $0.value.total) }
                        .sorted { $0.duration > $1.duration }
                )
            }
            .sorted { $0.duration > $1.duration }
    }

    private enum Edge { case top, bottom }

    /// Anything on the timeline whose extent the user may drag.
    ///
    /// A session's extent lives in its segments rather than in two plain
    /// fields, so both ends are written through to the first and last segment
    /// as well — otherwise the block would snap back on the next redraw, since
    /// that is what it is drawn from.
    ///
    /// Main-actor closures throughout: they read and write SwiftData models,
    /// and rescheduling a running session's end reminder from here reaches the
    /// notification service, which lives on the main actor too.
    @MainActor
    private struct Resizable {
        let start: @MainActor () -> Date
        let end: @MainActor () -> Date
        let setStart: @MainActor (Date) -> Void
        let setEnd: @MainActor (Date) -> Void

        init(entry: TimeEntry) {
            start = { entry.startedAt }
            end = { entry.endedAt }
            setStart = { entry.startedAt = $0 }
            setEnd = { entry.endedAt = $0 }
        }

        /// A running session has no recorded end, so dragging its lower edge
        /// changes when it is *due* to finish — which is what the countdown is
        /// showing — instead of inventing time it has not worked yet.
        init(runningSession session: WorkSession) {
            start = { session.startedAt }
            end = { Date.now.addingTimeInterval(session.remaining()) }
            setStart = { moment in
                session.startedAt = moment
                if let first = session.segments.min(by: { $0.startedAt < $1.startedAt }) {
                    first.startedAt = moment
                }
            }
            setEnd = { moment in
                let remaining = max(0, moment.timeIntervalSince(.now))
                let planned = session.elapsed() + remaining
                session.plannedMinutes = max(1, Int((planned / 60).rounded()))
                NotificationService.scheduleEndReminder(for: session)
            }
        }

        init(session: WorkSession) {
            start = { session.startedAt }
            end = { session.endedAt ?? .now }
            setStart = { moment in
                session.startedAt = moment
                if let first = session.segments.min(by: { $0.startedAt < $1.startedAt }) {
                    first.startedAt = moment
                }
            }
            setEnd = { moment in
                session.endedAt = moment
                let last = session.segments
                    .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
                last?.endedAt = moment
            }
        }
    }

    private func resizable(for block: TimelineBlock) -> Resizable? {
        if let entry = entry(for: block) { return Resizable(entry: entry) }
        guard let session = session(for: block) else { return nil }
        switch session.status {
        case .completed: return Resizable(session: session)
        case .active: return Resizable(runningSession: session)
        // Paused work has no end to move until it is resumed or finished.
        case .paused: return nil
        }
    }

    private func session(for block: TimelineBlock) -> WorkSession? {
        guard block.kind == .session else { return nil }
        return sessions.first { block.id.hasPrefix("session-\($0.id)") }
    }

    @ViewBuilder
    private func resizeHandle(_ target: Resizable?, isHovered: Bool, edge: Edge) -> some View {
        if let target {
            ZStack {
                Color.clear
                // A visible grip, so it is discoverable rather than something
                // you have to know is there.
                if isHovered {
                    Capsule()
                        .fill(Theme.label.opacity(0.55))
                        .frame(width: 26, height: 3)
                }
            }
            .contentShape(Rectangle())
            .frame(height: Self.handleHeight)
            .onHover { inside in
                // set(), not push()/pop(): a drag that ends outside the view
                // never delivers the matching exit, and an unbalanced stack
                // leaves the resize cursor stuck across the whole app.
                if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragOrigin == nil {
                            dragOrigin = (target.start(), target.end())
                        }
                        guard let origin = dragOrigin else { return }
                        let delta = TimeInterval(value.translation.height / hourHeight) * 3600
                        switch edge {
                        case .top:
                            let moved = geometry.snapped(origin.start.addingTimeInterval(delta))
                            target.setStart(min(moved, origin.end.addingTimeInterval(-5 * 60)))
                        case .bottom:
                            let moved = geometry.snapped(origin.end.addingTimeInterval(delta))
                            target.setEnd(max(moved, origin.start.addingTimeInterval(5 * 60)))
                        }
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        NSCursor.arrow.set()
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
        let anchorDate: Date? = isToday ? .now : blocks.map(\.start).min()
        guard let anchorDate else { return }
        let row = max(0, geometry.row(for: anchorDate) - 1)
        proxy.scrollTo(HourAnchor(hour: row), anchor: .top)
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
                // Labelled by the clock time actually at this offset, which is
                // not the row index on a day a DST change lands in.
                Text(Format.hourLabel(geometry.hour(atRow: hour)))
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
    let entries: [LegendEntry]
    @Binding var grouping: String

    /// How many fit before the row starts to crowd the timeline it labels.
    private static let shown = 4

    @State private var isShowingAll = false

    private var mode: TimelineGrouping {
        TimelineGrouping(rawValue: grouping) ?? .category
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if entries.isEmpty {
                Text("Nothing tracked yet today — colours here will name what you were in")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .lineLimit(1)
            } else {
                ForEach(entries.prefix(Self.shown)) { entry in
                    swatch(entry)
                }
                // A button, not a label: the point of a key is that nothing in
                // it is unreachable.
                Button {
                    isShowingAll = true
                } label: {
                    Text(entries.count > Self.shown
                         ? "+\(entries.count - Self.shown) more"
                         : "Details")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: Theme.Space.s)

            Menu {
                Picker("Group activity", selection: $grouping) {
                    ForEach(TimelineGrouping.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help(mode.detail)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 34)
        .background(Theme.surface.opacity(0.5))
        .popover(isPresented: $isShowingAll) {
            LegendDetail(entries: entries, mode: mode)
        }
    }

    private func swatch(_ entry: LegendEntry) -> some View {
        HStack(spacing: Theme.Space.xs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 8, height: 8)
            Text(entry.name)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
            Text(Format.compact(entry.duration))
                .font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(Theme.tertiaryLabel)
        }
        .fixedSize()
    }

}

/// The full key: every group, and — grouping by category — the apps filed into
/// it, so a wrong answer can be corrected where it is noticed rather than
/// somewhere else in Settings.
private struct LegendDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    let entries: [LegendEntry]
    let mode: TimelineGrouping

    @State private var expanded: Set<String> = []

    /// Beyond this the list scrolls; below it the popover is exactly as tall as
    /// its contents.
    private static let maximumHeight: CGFloat = 440

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(mode == .category ? "Today by category" : "Today by app")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, Theme.Space.xs)

            ForEach(entries) { entry in
                row(entry)
                if expanded.contains(entry.name) {
                    ForEach(entry.apps) { app in
                        appRow(app)
                    }
                }
            }

            if mode == .category {
                Text("Open a category to see which apps it holds, and move any that are filed wrongly.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.l)
    }

    var body: some View {
        // A ScrollView is greedy — given one, the popover takes whatever height
        // it is offered and leaves the rest empty. Short lists are laid out
        // plainly so the popover fits them, and only a list that would overflow
        // gets a scroller.
        Group {
            if estimatedHeight > Self.maximumHeight {
                ScrollView { content }
                    .frame(height: Self.maximumHeight)
            } else {
                content
            }
        }
        .frame(width: 340)
    }

    /// Close enough to decide whether scrolling is needed; the exact height
    /// comes from layout in the common case.
    private var estimatedHeight: CGFloat {
        let expandedApps = entries
            .filter { expanded.contains($0.name) }
            .reduce(0) { $0 + $1.apps.count }
        let header: CGFloat = 30
        let rows = CGFloat(entries.count) * 26
        let appRows = CGFloat(expandedApps) * 34
        let footer: CGFloat = mode == .category ? 40 : 0
        return header + rows + appRows + footer + Theme.Space.l * 2
    }

    /// Grouping by app leaves nothing to expand, so those rows are plain text
    /// rather than a disabled button — disabling one dims its whole content,
    /// which reads as unavailable rather than as merely not expandable.
    @ViewBuilder
    private func row(_ entry: LegendEntry) -> some View {
        if mode == .category {
            Button {
                if expanded.contains(entry.name) { expanded.remove(entry.name) }
                else { expanded.insert(entry.name) }
            } label: {
                rowContent(entry)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(entry)
        }
    }

    private func rowContent(_ entry: LegendEntry) -> some View {
        HStack(spacing: Theme.Space.s) {
            if mode == .category {
                Image(systemName: expanded.contains(entry.name) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
                    .frame(width: 10)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 9, height: 9)
            Text(entry.name)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.label)
            Spacer(minLength: Theme.Space.m)
            Text(Format.compact(entry.duration))
                .font(Theme.Font.body.monospacedDigit())
                .foregroundStyle(Theme.label)
            Text(Format.percent(entry.fraction))
                .font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 40, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func appRow(_ app: LegendEntry.AppShare) -> some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
                Text(Format.compact(app.duration))
                    .font(Theme.Font.micro.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            Spacer(minLength: Theme.Space.s)
            CategoryPicker(selection: Binding(
                get: {
                    AppCategorizer.category(forBundleIdentifier: app.bundleIdentifier,
                                            appName: app.name)
                },
                set: {
                    AppCategoryRule.assign($0, bundleIdentifier: app.bundleIdentifier,
                                           appName: app.name, in: context)
                    model.paletteDidChange()
                }
            ))
            .frame(width: 168)
        }
        .padding(.leading, 22)
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
