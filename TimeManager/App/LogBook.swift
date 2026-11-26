import Foundation
import SwiftData
import SwiftUI

/// What has been typed into a log form but not saved yet.
///
/// A value type so a form can hold one in `@State`, and the menu bar can keep
/// one on `AppModel` where it outlives the popover.
struct LogDraft: Equatable {
    var tabID: UUID?
    var resumePoint = ""
    var done = ""
    var noteIDs: Set<UUID> = []

    /// Whether there is anything worth saving. Whitespace is not.
    var hasText: Bool {
        !LogBook.clean(resumePoint).isEmpty || !LogBook.clean(done).isEmpty
    }

    mutating func clearText() {
        resumePoint = ""
        done = ""
        noteIDs = []
    }
}

/// A heading in the Log sidebar and the tabs under it.
struct LogSection: Identifiable {
    /// Empty for the tabs that sit under no heading.
    let group: String
    let tabs: [LogTab]
    var id: String { group }
}

/// The rules of the Log, kept out of the views so they can be tested and so
/// every surface that writes an entry — the Log pane, the review sheet, the
/// menu bar — writes it the same way.
///
/// Every mutation saves before it returns. "Saved" on screen has to mean the
/// entry is on disk, not that it is sitting in a context that a crash would
/// take with it.
@MainActor
enum LogBook {

    /// Trims surrounding whitespace and blank lines, leaving the text inside
    /// alone — a list typed one item per line stays a list.
    nonisolated static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A failed write must not stay pending for autosave, or a retry could
    /// duplicate an entry and a failed deletion could disappear later anyway.
    /// Log forms hold their text in drafts, outside the context's rollback.
    private static func persist(in context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }

    private enum WriteError: LocalizedError {
        case readOnly
        var errorDescription: String? { "This Log store is read-only. Your changes have not been saved." }
    }

    /// SwiftData rejects a read-only save before processing its pending
    /// changes; rollback then cannot reliably restore the relationship cache.
    /// Refuse the mutation before changing any model in that case.
    private static func requireWritable(in context: ModelContext) throws {
        guard context.container.configurations.allSatisfy(\.allowsSave) else { throw WriteError.readOnly }
    }

    // MARK: - Tabs

    /// Creates a tab at the end of the list, in a colour the other tabs are
    /// not using where one is free.
    @discardableResult
    static func createTab(
        name: String,
        group: String = "",
        in context: ModelContext,
        at date: Date = .now
    ) throws -> LogTab? {
        let trimmed = clean(name)
        guard !trimmed.isEmpty else { return nil }
        let existing = try allTabs(in: context)
        let tab = LogTab(
            name: trimmed,
            group: canonicalGroup(group, among: existing),
            colorSlot: nextColorSlot(among: existing),
            sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1,
            createdAt: date
        )
        try requireWritable(in: context)
        context.insert(tab)
        try persist(in: context)
        return tab
    }

    static func rename(_ tab: LogTab, to name: String, in context: ModelContext) throws {
        let trimmed = clean(name)
        guard !trimmed.isEmpty, trimmed != tab.name else { return }
        try requireWritable(in: context)
        tab.name = trimmed
        try persist(in: context)
    }

    /// Puts a tab under a heading — an existing one, a new one, or none. It
    /// goes to the end of its new section.
    static func move(_ tab: LogTab, toGroup group: String, in context: ModelContext) throws {
        let existing = try allTabs(in: context)
        let target = canonicalGroup(group, among: existing.filter { $0.id != tab.id })
        guard target != tab.group else { return }
        try requireWritable(in: context)
        tab.group = target
        tab.sortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        try persist(in: context)
    }

    /// Renames a heading, which moves every tab under it. Renaming onto an
    /// existing heading merges the two.
    static func renameGroup(_ old: String, to new: String, in context: ModelContext) throws {
        let from = clean(old)
        guard !from.isEmpty else { return }
        let tabs = try allTabs(in: context)
        let others = tabs.filter { $0.group != from }
        let target = canonicalGroup(new, among: others)
        try requireWritable(in: context)
        for tab in tabs where tab.group == from {
            tab.group = target
        }
        try persist(in: context)
    }

    static func setArchived(_ tab: LogTab, _ archived: Bool, in context: ModelContext) throws {
        guard tab.isArchived != archived else { return }
        try requireWritable(in: context)
        tab.isArchived = archived
        if !archived {
            // Back at the end of its section rather than wherever it used to
            // sit, which is where someone unarchiving it will look.
            let existing = try allTabs(in: context)
            tab.sortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        }
        try persist(in: context)
    }

    static func setColor(_ tab: LogTab, slot: Int, in context: ModelContext) throws {
        try requireWritable(in: context)
        tab.colorSlot = slot
        try persist(in: context)
    }

    /// Deletes a tab and every entry in it.
    static func delete(_ tab: LogTab, in context: ModelContext) throws {
        try requireWritable(in: context)
        // Deleted explicitly as well as by the cascade: an in-memory store
        // does not always run the cascade before the next fetch, and a
        // stranded entry with no tab would be invisible but still on disk.
        for entry in tab.entries { context.delete(entry) }
        context.delete(tab)
        try persist(in: context)
    }

    /// Reorders the tabs of one section. The section's tabs swap the sort
    /// positions they already hold among themselves, so no other section moves.
    static func reorder(
        _ section: [LogTab],
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in context: ModelContext
    ) throws {
        try requireWritable(in: context)
        var reordered = section
        reordered.move(fromOffsets: source, toOffset: destination)
        let slots = section.map(\.sortIndex).sorted()
        for (tab, index) in zip(reordered, slots) {
            tab.sortIndex = index
        }
        // Two tabs can hold the same index after an import or an old bug;
        // spread them so the order just chosen is the order that sticks.
        if Set(slots).count != slots.count {
            let base = slots.first ?? 0
            for (offset, tab) in reordered.enumerated() { tab.sortIndex = base + offset }
        }
        try persist(in: context)
    }

    // MARK: - Reading tabs

    static func allTabs(in context: ModelContext) throws -> [LogTab] {
        try context.fetch(FetchDescriptor<LogTab>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    /// The tab a session or a remembered preference points at, if it still
    /// exists and is not archived. Anything else reads as "no tab".
    static func activeTab(id: UUID?, in tabs: [LogTab]) -> LogTab? {
        guard let id else { return nil }
        return tabs.first { $0.id == id && !$0.isArchived }
    }

    static func activeTab(id: UUID?, in context: ModelContext) -> LogTab? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<LogTab>(predicate: #Predicate { $0.id == id })
        guard let tab = try? context.fetch(descriptor).first, !tab.isArchived else { return nil }
        return tab
    }

    /// The Log sidebar: tabs under no heading first, then each heading in the
    /// order its earliest tab sits, tabs in their own order. Archived tabs are
    /// left out; they have a section of their own.
    static func sections(_ tabs: [LogTab]) -> [LogSection] {
        let active = tabs.filter { !$0.isArchived }.sorted(by: tabOrder)
        var order: [String] = []
        var grouped: [String: [LogTab]] = [:]
        for tab in active {
            if grouped[tab.group] == nil { order.append(tab.group) }
            grouped[tab.group, default: []].append(tab)
        }
        // Ungrouped tabs lead whatever their sort positions say.
        if let index = order.firstIndex(of: ""), index != 0 {
            order.remove(at: index)
            order.insert("", at: 0)
        }
        return order.map { LogSection(group: $0, tabs: grouped[$0] ?? []) }
    }

    static func archived(_ tabs: [LogTab]) -> [LogTab] {
        tabs.filter(\.isArchived).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every heading in use, in sidebar order, for the "Move to group" menu.
    static func knownGroups(_ tabs: [LogTab]) -> [String] {
        var result: [String] = []
        for group in sections(tabs).map(\.group) + archived(tabs).map(\.group)
        where !group.isEmpty && !result.contains(group) {
            result.append(group)
        }
        return result
    }

    private static func tabOrder(_ a: LogTab, _ b: LogTab) -> Bool {
        if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
        return a.createdAt < b.createdAt
    }

    /// "research" typed where "Research" already exists is the same heading,
    /// not a second one that looks identical in the sidebar.
    static func canonicalGroup(_ group: String, among tabs: [LogTab]) -> String {
        let trimmed = clean(group)
        guard !trimmed.isEmpty else { return "" }
        return tabs.map(\.group).first {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        } ?? trimmed
    }

    private static func nextColorSlot(among tabs: [LogTab]) -> Int {
        let used = Set(tabs.map(\.colorSlot))
        if let free = CategoryPalette.swatches.first(where: { !used.contains($0.slot) }) {
            return free.slot
        }
        let count = max(1, CategoryPalette.swatches.count)
        return CategoryPalette.swatches[tabs.count % count].slot
    }

    // MARK: - Entries

    /// Saves an entry. Nil when there is nothing to save — both fields empty.
    ///
    /// When a session is given, the entry keeps its ID, its title and the time
    /// it had been worked at `date`. Without one the entry carries no duration
    /// at all: the log never invents one.
    @discardableResult
    static func addEntry(
        to tab: LogTab,
        resumePoint: String,
        done: String,
        session: WorkSession? = nil,
        noteIDs: Set<UUID> = [],
        at date: Date = .now,
        in context: ModelContext
    ) throws -> LogEntry? {
        let resume = clean(resumePoint)
        let did = clean(done)
        guard !resume.isEmpty || !did.isEmpty else { return nil }
        try requireWritable(in: context)
        let entry = LogEntry(tab: tab, recordedAt: date, resumePoint: resume, done: did)
        if let session {
            entry.sessionID = session.id
            entry.sessionTitle = session.title
            entry.workedSeconds = session.elapsed(at: date)
        }
        entry.notes = tab.notes.filter { noteIDs.contains($0.id) }
        context.insert(entry)
        tab.entries.append(entry)
        try persist(in: context)
        return entry
    }

    /// Saves the draft into the tab it names. Nil when there is no tab or no
    /// text, which is how "Don't log" and an untouched form both say no.
    @discardableResult
    static func save(
        _ draft: LogDraft,
        session: WorkSession? = nil,
        at date: Date = .now,
        in context: ModelContext
    ) throws -> LogEntry? {
        guard draft.hasText, let tab = activeTab(id: draft.tabID, in: context) else { return nil }
        return try addEntry(to: tab, resumePoint: draft.resumePoint, done: draft.done,
                            session: session, noteIDs: draft.noteIDs, at: date, in: context)
    }

    /// Rewrites an entry. Refuses to empty both fields — that is a delete, and
    /// should be asked for as one. Returns whether anything was written.
    @discardableResult
    static func update(
        _ entry: LogEntry,
        resumePoint: String,
        done: String,
        recordedAt: Date,
        tab: LogTab? = nil,
        noteIDs: Set<UUID>? = nil,
        at now: Date = .now,
        in context: ModelContext
    ) throws -> Bool {
        let resume = clean(resumePoint)
        let did = clean(done)
        guard !resume.isEmpty || !did.isEmpty else { return false }
        try requireWritable(in: context)
        entry.resumePoint = resume
        entry.done = did
        entry.recordedAt = recordedAt
        if let tab, tab.id != entry.tab?.id {
            entry.tab?.entries.removeAll { $0.id == entry.id }
            entry.tab = tab
            tab.entries.append(entry)
        }
        let linkedIDs = noteIDs ?? Set(entry.notes.map(\.id))
        entry.notes = (entry.tab?.notes ?? []).filter { linkedIDs.contains($0.id) }
        entry.editedAt = now
        try persist(in: context)
        return true
    }

    static func delete(_ entry: LogEntry, in context: ModelContext) throws {
        try requireWritable(in: context)
        entry.tab?.entries.removeAll { $0.id == entry.id }
        context.delete(entry)
        try persist(in: context)
    }

    // MARK: - Reading entries

    /// Newest first, the way the Doc reads.
    static func history(for tab: LogTab) -> [LogEntry] {
        tab.entries.sorted(by: newestFirst)
    }

    /// The entry the "Pick up here" card shows: the newest one that says where
    /// to resume. An entry recording only what was done must not blank out the
    /// last instruction you left yourself.
    static func latestResumePoint(for tab: LogTab) -> LogEntry? {
        tab.entries.filter(\.hasResumePoint).max { newestFirst($1, $0) }
    }

    static func lastLogged(_ tab: LogTab) -> Date? {
        tab.entries.map(\.recordedAt).max()
    }

    private static func newestFirst(_ a: LogEntry, _ b: LogEntry) -> Bool {
        if a.recordedAt != b.recordedAt { return a.recordedAt > b.recordedAt }
        return a.id.uuidString > b.id.uuidString
    }

    // MARK: - Plain text

    /// The entries as the old Google Doc laid them out, newest first, for
    /// pasting into a Doc or anywhere else.
    static func plainText(for entries: [LogEntry]) -> String {
        entries.sorted(by: newestFirst).map(plainText(for:)).joined(separator: "\n\n\n")
    }

    static func plainText(for entry: LogEntry) -> String {
        var lines = [
            "Date: \(Format.logDocDate(entry.recordedAt))",
            "Time: \(Format.logDocTime(entry.recordedAt))",
            "",
            "Resume Point / Things to do",
        ]
        if entry.hasResumePoint { lines.append(entry.resumePoint) }
        lines.append("What was done in this session")
        if entry.hasDone { lines.append(entry.done) }
        return lines.joined(separator: "\n")
    }
}
