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
    @Query private var breaks: [BreakRecord]
    @Query private var activity: [ActivityRecord]

    @State private var selection: TimelineBlock?
    @State private var editingEntry: TimeEntry?
    @State private var editingSession: WorkSession?
    @State private var pendingDelete: TimelineBlock?
    @State private var writeError: String?
    /// The block being swept out. A reference the timeline itself never reads,
    /// so a creation drag redraws the ghost and nothing else.
    @State private var draft = TimelineDraft()
    @State private var scroller = TimelineAutoScroller()

    @State private var hoveredRail: TimelineBlock?
    @State private var inspectorY: CGFloat = 0
    /// The panel's measured height, so it can be kept inside the track. A
    /// guessed constant is what used to push half of it off the bottom.
    @State private var inspectorHeight: CGFloat = 260
    @AppStorage("timelineGrouping") private var groupingRaw = TimelineGrouping.category.rawValue

    private static let gutterWidth: CGFloat = 52
    /// Wide enough to read as a continuous band of the day rather than a line
    /// of slivers; short app switches are only a few points tall.
    private static let railWidth: CGFloat = 20
    private static let railGap: CGFloat = 12
    private static let handleHeight: CGFloat = 6

    init(day: Date, hourHeight: Binding<CGFloat>) {
        self.day = day
        self._hourHeight = hourHeight

        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _sessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
        _entries = Query(filter: #Predicate<TimeEntry> { $0.startedAt >= start && $0.startedAt < end },
                         sort: \.startedAt)
        _breaks = Query(filter: #Predicate<BreakRecord> { $0.startedAt >= start && $0.startedAt < end },
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
            + breaks.map(TimelineBlock.block(for:))
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
        .onExitCommand(perform: closeInspector)
        .confirmationDialog("Delete this block?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let block = pendingDelete { delete(block) }
                pendingDelete = nil
            }
        } message: { Text("This removes the recorded block. Linked Log entries and project notes are kept.") }
        .alert("Couldn’t save timeline", isPresented: Binding(
            get: { writeError != nil }, set: { if !$0 { writeError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(writeError ?? "") }
        .overlay(alignment: .bottom) {
            // Deliberately not `blocks.isEmpty`, which would merge the day's
            // activity a second time on every pass just to ask whether there
            // is any.
            if sessions.isEmpty, entries.isEmpty, breaks.isEmpty, activity.isEmpty { emptyHint }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let laneWidth = max(40, proxy.size.width - Self.railWidth - Self.railGap)
            let laneX = Self.railWidth + Self.railGap
            // Built once per pass. The ribbon, the cards and the hover readout
            // each used to ask for `blocks` separately, and every one of those
            // re-merged the whole day's tracked activity.
            let ribbons = blocks.filter(\.kind.isRibbon)
            let cards = TimelineLayout.place(blocks.filter { !$0.kind.isRibbon },
                                             in: geometry, minimumHeight: 26)
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

                CreationLayer(geometry: geometry, laneX: laneX, laneWidth: laneWidth,
                              draft: draft, scroller: scroller, onCreate: create)

                ActivityRail(blocks: ribbons, geometry: geometry)
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
                        hoveredRail = ribbons.first { $0.start <= moment && moment <= $0.end }
                    }
                    .gesture(SpatialTapGesture(coordinateSpace: .named(TimelineSpace.track)).onEnded { value in
                        let moment = geometry.date(for: value.location.y)
                        guard let block = ribbons.first(where: { $0.start <= moment && moment < $0.end }) else { return }
                        closeInspector()
                        inspectorY = value.location.y
                        selection = block
                    })
                    .accessibilityIdentifier("timeline.activityRail")
                // The rail has useful detail too; a click should keep it open
                // instead of requiring the pointer to stay perfectly still.
                if let hoveredRail {
                    railReadout(hoveredRail)
                        .offset(x: Self.railWidth + 6,
                                y: max(0, geometry.y(for: hoveredRail.start) - 4))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                ForEach(cards) { placed in
                    let width = laneWidth / CGFloat(placed.laneCount)
                    LaneCard(
                        placed: placed,
                        geometry: geometry,
                        hourHeight: hourHeight,
                        scroller: scroller,
                        x: laneX + width * CGFloat(placed.lane),
                        width: width,
                        handleHeight: Self.handleHeight,
                        target: resizable(for: placed.block),
                        // Only a hand-made block can be picked up whole; a
                        // session is moved by its edges or not at all.
                        isMovable: entry(for: placed.block) != nil,
                        onTap: { open(placed) },
                        onMove: { delta in move(placed.block, by: delta) },
                        onResize: { edge, moment in resize(placed.block, edge: edge, to: moment) }
                    )
                    .contextMenu {
                        Button(entry(for: placed.block) != nil || session(for: placed.block) != nil ? "Edit…" : "Show Details…") { open(placed) }
                        if entry(for: placed.block) != nil || session(for: placed.block) != nil || breakRecord(for: placed.block) != nil {
                            Button("Delete…", role: .destructive) { pendingDelete = placed.block }
                        }
                    }
                }

                DraftGhost(geometry: geometry, laneX: laneX, laneWidth: laneWidth, draft: draft)

                if isToday {
                    NowIndicator(geometry: geometry)
                }

                if editingEntry != nil || editingSession != nil || selection != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: proxy.size.width, height: geometry.totalHeight)
                        .onTapGesture(perform: closeInspector)
                        .zIndex(9)
                }

                inspector(laneX: laneX, laneWidth: laneWidth, trackWidth: proxy.size.width)
            }
            .coordinateSpace(name: TimelineSpace.track)
            .background(TimelineScrollViewFinder(scroller: scroller))
        }
        // The ghost of a block just created stays until its card arrives, so
        // the two are never both missing for a frame.
        .onChange(of: sessions.map(\.persistentModelID)) { _, _ in
            if let editingSession, !sessions.contains(where: { $0 === editingSession }) {
                self.editingSession = nil
            }
        }
        .onChange(of: entries.map(\.id)) { _, ids in
            if let editingEntry, !entries.contains(where: { $0 === editingEntry }) {
                self.editingEntry = nil
            }
            guard let id = draft.awaiting, ids.contains(id) else { return }
            draft.range = nil
            draft.awaiting = nil
        }
        .onChange(of: day) {
            draft.range = nil
            draft.awaiting = nil
        }
    }

    // MARK: - Creating

    private func create(from start: Date, to end: Date) {
        let entry = TimeEntry(title: "", category: "", startedAt: start, endedAt: end)
        context.insert(entry)
        do { try context.save() }
        catch {
            context.rollback()
            draft.range = nil
            writeError = error.localizedDescription
            return
        }
        draft.awaiting = entry.id
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

    private func closeInspector() {
        editingEntry = nil
        editingSession = nil
        selection = nil
    }

    private func delete(_ block: TimelineBlock) {
        do {
            if let entry = entry(for: block) {
                context.delete(entry)
                try context.save()
            } else if let session = session(for: block) {
                try model.deleteSession(session)
            } else if let record = breakRecord(for: block) {
                try model.deleteBreak(record)
            }
            closeInspector()
        } catch {
            context.rollback()
            writeError = error.localizedDescription
        }
    }

    // MARK: - Cards

    /// Opens whatever the card stands for, beside itself.
    private func open(_ placed: PlacedBlock) {
        inspectorY = placed.y
        selection = nil
        editingEntry = nil
        editingSession = nil
        if let entry = entry(for: placed.block) {
            editingEntry = entry
        } else if let session = session(for: placed.block) {
            editingSession = session
        } else {
            selection = placed.block
        }
    }

    /// Applies a finished move. One write, at the end of the gesture.
    private func move(_ block: TimelineBlock, by delta: TimeInterval) {
        guard let entry = entry(for: block) else { return }
        entry.startedAt = entry.startedAt.addingTimeInterval(delta)
        entry.endedAt = entry.endedAt.addingTimeInterval(delta)
        try? context.save()
    }

    private func resize(_ block: TimelineBlock, edge: ResizeEdge, to moment: Date) {
        guard let target = resizable(for: block) else { return }
        switch edge {
        case .top: target.setStart(moment)
        case .bottom: target.setEnd(moment)
        }
        try? context.save()
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
            let panelWidth = min(CGFloat(300), max(1, trackWidth - 8))
            // Sits beside the lane where there is room, and tucks inside the
            // track when the pane is narrow.
            let x = min(max(laneX + Theme.Space.s, 0), max(0, trackWidth - panelWidth - 4))
            // Clamped against the panel's own measured height rather than the
            // 260 points once assumed here.
            let visible = scroller.visibleDayRange
            let availableHeight = visible.map { max(120, $0.upperBound - $0.lowerBound - 16) } ?? geometry.totalHeight
            let shownHeight = min(inspectorHeight, availableHeight)
            let y = geometry.panelTop(anchoredAt: inspectorY, height: shownHeight, visibleRange: visible)

            ScrollView {
                Group {
                    if let entry = editingEntry {
                        TimeEntryEditor(entry: entry, width: panelWidth) { editingEntry = nil }
                    } else if let session = editingSession {
                        SessionEditor(session: session, model: model, width: panelWidth) { editingSession = nil }
                    } else if let block = selection {
                        if let record = breakRecord(for: block) {
                            TimelineBlockDetail(block: block, onDelete: {
                                do {
                                    try model.deleteBreak(record)
                                    selection = nil
                                } catch { writeError = error.localizedDescription }
                            }, onClose: { selection = nil })
                        } else {
                            TimelineBlockDetail(block: block) { selection = nil }
                        }
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
            }
            .frame(width: panelWidth, height: shownHeight)
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

    private func resizable(for block: TimelineBlock) -> Resizable? {
        if let entry = entry(for: block) { return Resizable(entry: entry) }
        if let record = breakRecord(for: block) {
            return model.isRunningBreak(record)
                ? Resizable(runningBreak: record, model: model)
                : Resizable(breakRecord: record)
        }
        guard let session = session(for: block) else { return nil }
        switch session.status {
        case .completed: return Resizable(session: session, model: model)
        case .active: return Resizable(runningSession: session, model: model)
        // Paused work has no end to move until it is resumed or finished.
        case .paused: return nil
        }
    }

    private func breakRecord(for block: TimelineBlock) -> BreakRecord? {
        guard block.kind == .rest else { return nil }
        return breaks.first { "break-\($0.id)" == block.id }
    }

    private func session(for block: TimelineBlock) -> WorkSession? {
        guard block.kind == .session else { return nil }
        return sessions.first { block.id.hasPrefix("session-\($0.id)") }
    }

    private func entry(for block: TimelineBlock) -> TimeEntry? {
        guard block.kind == .entry else { return nil }
        return entries.first { "entry-\($0.id)" == block.id }
    }

    /// Shown only on a genuinely empty day — the one place the drag gesture is
    /// worth spelling out, since nothing on screen implies it.
    private var emptyHint: some View {
        Text("Double-click or drag empty timeline space to add a block")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.tertiaryLabel)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.surface, in: Capsule())
            .padding(.bottom, Theme.Space.xl)
            .allowsHitTesting(false)
    }

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

// MARK: - Creating

/// A block being swept out on empty lane space, before it is written down.
private struct DraftRange: Equatable {
    var anchor: Date
    var current: Date
    var lower: Date { min(anchor, current) }
    var upper: Date { max(anchor, current) }
}

/// Shared by the layer the drag happens on and the ghost drawn above the cards.
/// Only the ghost reads the range, so only the ghost redraws as it changes.
@MainActor
@Observable
private final class TimelineDraft {
    var range: DraftRange?
    /// The entry just created from the draft. The ghost is held until its card
    /// is on screen.
    @ObservationIgnored var awaiting: UUID?
}

/// Empty lane space. Dragging here sweeps out a block the way dragging in a
/// calendar does; the result is committed on release and opened for naming.
///
/// Its own view, holding nothing that draws, so a drag here does not rebuild
/// the day's blocks on every event the way it did as part of the timeline.
private struct CreationLayer: View {
    let geometry: TimelineGeometry
    let laneX: CGFloat
    let laneWidth: CGFloat
    let draft: TimelineDraft
    let scroller: TimelineAutoScroller
    let onCreate: (Date, Date) -> Void

    @State private var tracker = DragTracker()
    @State private var anchor: CGFloat = 0
    @State private var pointerY: CGFloat = 0

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: laneWidth, height: geometry.totalHeight)
            .offset(x: laneX)
            .accessibilityIdentifier("timeline.emptyLane")
            .help("Double-click to add a block, or drag to choose its length")
            .onContinuousHover { phase in
                if case .active(let point) = phase { pointerY = point.y }
            }
            .contextMenu {
                Button("Add Block Here") { create(at: pointerY) }
            }
            .simultaneousGesture(
                SpatialTapGesture(count: 2, coordinateSpace: .named(TimelineSpace.track))
                    .onEnded { create(at: $0.location.y) }
            )
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(TimelineSpace.track))
                    .onChanged { value in
                        if draft.range == nil || draft.awaiting != nil {
                            draft.awaiting = nil
                            anchor = value.startLocation.y
                        }
                        tracker.record(value.translation.height)
                        update()
                        scroller.follow { moved in
                            tracker.scrolled += moved
                            update()
                        }
                    }
                    .onEnded { _ in
                        scroller.stop()
                        guard let range = draft.range else { return }
                        // A flick that collapses to nothing still means "a block
                        // here", so it gets a sensible default length.
                        let fallback = geometry.newBlockRange(at: geometry.y(for: range.lower))
                        let lower = range.upper > range.lower ? range.lower : fallback.start
                        let upper = range.upper > range.lower ? range.upper : fallback.end
                        // Left on screen, at the size it will be created at,
                        // until the card replaces it.
                        draft.range = DraftRange(anchor: lower, current: upper)
                        onCreate(lower, upper)
                    }
            )
    }

    private func create(at y: CGFloat) {
        scroller.stop()
        let range = geometry.newBlockRange(at: y)
        draft.range = DraftRange(anchor: range.start, current: range.end)
        onCreate(range.start, range.end)
    }

    /// The same minute grid the cards move on, so the ghost and the block it
    /// becomes agree, and no event redraws a ghost that has not moved.
    private func update() {
        let next = DraftRange(
            anchor: geometry.snapped(geometry.date(for: anchor), minutes: 1),
            current: geometry.snapped(geometry.date(for: anchor + tracker.total), minutes: 1)
        )
        guard next != draft.range else { return }
        draft.range = next
    }
}

private struct DraftGhost: View {
    let geometry: TimelineGeometry
    let laneX: CGFloat
    let laneWidth: CGFloat
    let draft: TimelineDraft

    var body: some View {
        if let range = draft.range {
            let top = geometry.y(for: range.lower)
            let height = max(4, geometry.y(for: range.upper) - top)
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .fill(Theme.accent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.block)
                        .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    Text("\(Format.timeOfDay(range.lower)) – \(Format.timeOfDay(range.upper))")
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

// MARK: - A card and its gestures

private enum ResizeEdge { case top, bottom }

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

    /// The running break. Its lower edge is when it is due to end — the same
    /// arrangement as a running session — so pulling it down is taking longer.
    init(runningBreak record: BreakRecord, model: AppModel) {
        start = { record.startedAt }
        end = { record.plannedEnd }
        setStart = { record.startedAt = $0 }
        setEnd = { model.setBreakEnd($0) }
    }

    /// A break that is over. Held at now, since a break that has ended cannot
    /// have been taken in the future.
    init(breakRecord record: BreakRecord) {
        start = { record.startedAt }
        end = { record.end }
        setStart = { record.startedAt = $0 }
        setEnd = { moment in
            let end = min(moment, .now)
            record.endedAt = end
            record.plannedEnd = max(record.plannedEnd, end)
        }
    }

    /// A running session has no recorded end, so dragging its lower edge
    /// changes when it is *due* to finish — which is what the countdown is
    /// showing — instead of inventing time it has not worked yet.
    init(runningSession session: WorkSession, model: AppModel) {
        start = { session.startedAt }
        end = { Date.now.addingTimeInterval(session.remaining()) }
        setStart = { moment in
            session.startedAt = moment
            if let first = session.segments.min(by: { $0.startedAt < $1.startedAt }) {
                first.startedAt = moment
            }
        }
        setEnd = { moment in
            // A minute is kept on the clock throughout. Dragging the lower
            // edge up to now would otherwise run the planned time out
            // mid-drag and end the session under the cursor — which is
            // Finish's job, not the drag handle's.
            let remaining = max(60, moment.timeIntervalSince(.now))
            let planned = session.elapsed() + remaining
            model.setPlannedMinutes(max(1, Int((planned / 60).rounded())), for: session)
        }
    }

    /// A finished session. Pulled past now it is not finished after all,
    /// which is what `resumeSession` sorts out; otherwise its end is held
    /// at now, since a finished session cannot end in the future without
    /// its last run counting time nobody has worked.
    init(session: WorkSession, model: AppModel) {
        start = { session.startedAt }
        end = { session.endedAt ?? .now }
        setStart = { moment in
            session.startedAt = moment
            if let first = session.segments.min(by: { $0.startedAt < $1.startedAt }) {
                first.startedAt = moment
            }
        }
        setEnd = { moment in
            guard !model.resumeSession(session, endingAt: moment) else { return }
            let end = min(moment, .now)
            session.endedAt = end
            let last = session.segments
                .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
            last?.endedAt = end
        }
    }
}

/// One card in the wide lane, and the gestures that move it.
///
/// The drag state lives here rather than up in the timeline, and that is the
/// whole point of this type. Held there, every event of a gesture re-evaluated
/// the entire track — the day's blocks rebuilt, the activity ribbon merged
/// again, every card laid out again, the store written and a running session's
/// notification rescheduled — so the card arrived late and in five-minute
/// jumps. Dragging now redraws one card, moves by the minute, and writes
/// exactly once, on release.
private struct LaneCard: View {
    let placed: PlacedBlock
    let geometry: TimelineGeometry
    let hourHeight: CGFloat
    let scroller: TimelineAutoScroller
    let x: CGFloat
    let width: CGFloat
    let handleHeight: CGFloat
    /// Nil when this block's extent is not the user's to change.
    let target: Resizable?
    /// Only a hand-made block can be picked up and moved whole.
    let isMovable: Bool
    let onTap: () -> Void
    let onMove: (TimeInterval) -> Void
    let onResize: (ResizeEdge, Date) -> Void

    /// Where the card is drawn when it is not where its block says.
    private struct Extent: Equatable {
        var start: Date
        var end: Date
    }

    /// Hover is local too: the grips used to be drawn from state in the
    /// timeline, so every card in the day was rebuilt as the pointer crossed
    /// any one of them.
    @State private var isHovered = false
    /// Where the drag has got to, before anything is written down.
    @State private var dragged: Extent?
    /// Where the card was dropped, held until the store says the same thing.
    ///
    /// Clearing the drag on release while the new times were still on their way
    /// back through the query drew the card for a frame at its old place, then
    /// at its new one — the flicker on every drop.
    @State private var dropped: Extent?
    @State private var tracker = DragTracker()

    /// The shortest a block may be dragged down to.
    private static let minimumLength: TimeInterval = 5 * 60

    private var shown: Extent {
        dragged ?? dropped ?? Extent(start: placed.block.start, end: placed.block.end)
    }
    private var isDragging: Bool { dragged != nil }

    private func points(_ seconds: TimeInterval) -> CGFloat {
        CGFloat(seconds / 3600) * hourHeight
    }

    private func seconds(_ points: CGFloat) -> TimeInterval {
        TimeInterval(points / hourHeight) * 3600
    }

    /// To the minute while dragging. Five-minute steps are nine points apart at
    /// a comfortable zoom, and a card that moves in nine-point jumps reads as
    /// stutter however promptly it arrives.
    private func snapped(_ date: Date) -> Date { geometry.snapped(date, minutes: 1) }

    var body: some View {
        // Relative to the block, so the moment the store catches up with a drop
        // both are zero and the card does not move.
        let startBy = shown.start.timeIntervalSince(placed.block.start)
        let endBy = shown.end.timeIntervalSince(placed.block.end)
        let height = max(6, placed.height + points(endBy - startBy))
        // Deliberately the committed block, not one built from where the drag
        // has got to. Handing the card a new block each frame re-runs its date
        // formatting, its text layout and its tooltip — work the eye cannot see
        // and the hand can feel. Moving the card is then nothing but an offset,
        // and SwiftUI can skip the card's body entirely.
        CardBlockView(block: placed.block, height: height, showsTooltip: !isDragging)
            .frame(width: max(24, width - 3), height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onHover { inside in
                // The card moves out from under the pointer as it is dragged,
                // so hover fires repeatedly mid-gesture. Redrawing for that is
                // the drag paying for a grip nobody is looking at.
                guard !isDragging else { return }
                isHovered = inside
            }
            .overlay { moveArea }
            .overlay(alignment: .top) { handle(.top) }
            .overlay(alignment: .bottom) { handle(.bottom) }
            .overlay(alignment: .topTrailing) { readout }
            .accessibilityIdentifier("timeline.block.\(placed.block.id)")
            .offset(x: x)
            // Sideways only: a card making room for a neighbour slides over
            // rather than jumping. Up and down is the hand's, and an animation
            // there would trail the pointer.
            .animation(.snappy(duration: 0.2), value: x)
            .animation(.snappy(duration: 0.2), value: width)
            .offset(y: placed.y + points(startBy))
            // Above its neighbours while it is being moved, so it is not drawn
            // behind the cards it passes.
            .zIndex(isDragging || dropped != nil ? 3 : 0)
            .onChange(of: placed.block.start) { settle() }
            .onChange(of: placed.block.end) { settle() }
    }

    /// The store has answered the drop. Where it answered exactly, nothing
    /// moves; where it rounded — a running session's end is kept in whole
    /// planned minutes — the card eases the difference rather than jumping it.
    private func settle() {
        guard dropped != nil, dragged == nil else { return }
        withAnimation(.snappy(duration: 0.15)) { dropped = nil }
    }

    /// Holds the card where it was let go, and gives up on the store after a
    /// moment: a write it refused never changes the block, so would never
    /// release the card otherwise.
    private func drop(at extent: Extent) {
        dropped = extent
        dragged = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard dropped == extent, dragged == nil else { return }
            withAnimation(.snappy(duration: 0.2)) { dropped = nil }
        }
    }

    /// Feeds a drag's position through, and keeps it moving while the timeline
    /// scrolls under a pointer held at the edge.
    private func follow(_ value: DragGesture.Value, _ apply: @escaping (TimeInterval) -> Void) {
        tracker.record(value.translation.height)
        apply(seconds(tracker.total))
        scroller.follow { moved in
            tracker.scrolled += moved
            apply(seconds(tracker.total))
        }
    }

    /// Where the block will land, since the card's own label is deliberately
    /// left as it was until the drag is committed.
    @ViewBuilder
    private var readout: some View {
        if isDragging {
            Text("\(Format.timeOfDay(shown.start)) – \(Format.timeOfDay(shown.end))")
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.raised, in: Capsule())
                .padding(3)
                .allowsHitTesting(false)
        }
    }

    /// The part of a card that opens it and drags it around: everything except
    /// the resize strips at either end.
    private var moveArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .padding(.vertical, handleHeight)
            .accessibilityIdentifier("timeline.card.\(placed.block.id)")
            .onTapGesture(count: 2, perform: onTap)
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .gesture(moveGesture, including: isMovable ? .all : .none)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TimelineSpace.track))
            .onChanged { value in
                follow(value) { raw in
                    let start = snapped(placed.block.start.addingTimeInterval(raw))
                    let next = Extent(start: start,
                                      end: start.addingTimeInterval(placed.block.duration))
                    // Most events land on the minute the card is already drawn at.
                    guard next != dragged else { return }
                    dragged = next
                }
            }
            .onEnded { _ in
                scroller.stop()
                guard let extent = dragged else { return }
                let delta = extent.start.timeIntervalSince(placed.block.start)
                guard delta != 0 else { dragged = nil; return }
                drop(at: extent)
                onMove(delta)
            }
    }

    @ViewBuilder
    private func handle(_ edge: ResizeEdge) -> some View {
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
            .frame(height: handleHeight)
            .onHover { inside in
                // set(), not push()/pop(): a drag that ends outside the view
                // never delivers the matching exit, and an unbalanced stack
                // leaves the resize cursor stuck across the whole app.
                if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(resizeGesture(edge, target: target))
        }
    }

    private func resizeGesture(_ edge: ResizeEdge, target: Resizable) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(TimelineSpace.track))
            .onChanged { value in
                follow(value) { raw in
                    var next = Extent(start: placed.block.start, end: placed.block.end)
                    switch edge {
                    case .top:
                        let limit = placed.block.end.addingTimeInterval(-Self.minimumLength)
                        next.start = min(snapped(placed.block.start.addingTimeInterval(raw)), limit)
                    case .bottom:
                        let limit = placed.block.start.addingTimeInterval(Self.minimumLength)
                        next.end = max(snapped(placed.block.end.addingTimeInterval(raw)), limit)
                    }
                    guard next != dragged else { return }
                    dragged = next
                }
            }
            .onEnded { _ in
                scroller.stop()
                NSCursor.arrow.set()
                guard let extent = dragged else { return }
                switch edge {
                case .top:
                    guard extent.start != placed.block.start else { dragged = nil; return }
                    drop(at: extent)
                    onResize(.top, extent.start)
                case .bottom:
                    guard extent.end != placed.block.end else { dragged = nil; return }
                    drop(at: extent)
                    onResize(.bottom, extent.end)
                }
            }
    }
}
