import AppKit
import SwiftData
import SwiftUI

/// The Log: one tab per thing you keep coming back to, each with where you
/// stopped, a place to write the next entry, and everything written before.
struct LogPaneView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \LogTab.sortIndex) private var tabs: [LogTab]

    /// The tab on screen, remembered across launches.
    @AppStorage("log.selectedTabID") private var selectedRaw = ""
    @State private var creationError: String?

    /// Opens the start sheet with this tab chosen.
    let onStartSession: (UUID) -> Void

    private static let sidebarWidth: CGFloat = 220

    private var selection: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: selectedRaw) },
            set: { selectedRaw = $0?.uuidString ?? "" }
        )
    }

    private var selectedTab: LogTab? {
        guard let id = selection.wrappedValue else { return nil }
        return tabs.first { $0.id == id }
    }

    var body: some View {
        Group {
            if tabs.isEmpty {
                LogEmptyState { name in
                    do {
                        if let tab = try LogBook.createTab(name: name, in: context) {
                            selection.wrappedValue = tab.id
                            return true
                        }
                        return false
                    } catch {
                        creationError = error.localizedDescription
                        return false
                    }
                }
            } else {
                HStack(spacing: 0) {
                    LogSidebar(tabs: tabs, selection: selection)
                        .frame(width: Self.sidebarWidth)
                    Divider()
                    if let tab = selectedTab {
                        LogTabDetail(
                            tab: tab,
                            draft: Binding(
                                get: { model.logDrafts[tab.id] ?? LogDraft(tabID: tab.id) },
                                set: { model.logDrafts[tab.id] = $0 }
                            ),
                            onStartSession: { onStartSession(tab.id) }
                        )
                        .id(tab.id)
                    } else {
                        Text("Choose a tab")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.tertiaryLabel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Theme.canvas)
        .onAppear(perform: ensureSelection)
        .onChange(of: tabs.map(\.id)) { _, _ in ensureSelection() }
        .alert("Couldn't create tab", isPresented: Binding(
            get: { creationError != nil },
            set: { if !$0 { creationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(creationError ?? "")
        }
    }

    /// Keeps a tab on screen: the remembered one if it still exists, else the
    /// first active one.
    private func ensureSelection() {
        let ids = Set(tabs.map(\.id))
        model.logDrafts = model.logDrafts.filter { ids.contains($0.key) }
        if selectedTab != nil { return }
        let first = LogBook.sections(tabs).first?.tabs.first ?? tabs.first
        selection.wrappedValue = first?.id
    }
}

// MARK: - Empty state

/// The first thing anyone sees in the Log, before there is a tab.
private struct LogEmptyState: View {
    let onCreate: (String) -> Bool
    @State private var name = ""

    private static let suggestions = ["Research", "Internship", "Business"]

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "book.pages")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            VStack(spacing: Theme.Space.xs) {
                Text("Start a log for each thing you come back to")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text("At the end of a session, write where you stopped and what's next. When you come back, it's the first thing you see.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            HStack(spacing: Theme.Space.s) {
                TextField("Name a tab — a course, a paper, a client…", text: $name)
                    .accessibilityIdentifier("log.empty.name")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(create)
                Button("Create", action: create)
                    .accessibilityIdentifier("log.empty.create")
                    .keyboardShortcut(.defaultAction)
                    .disabled(LogBook.clean(name).isEmpty)
            }
            HStack(spacing: Theme.Space.s) {
                Text("Or start with")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { _ = onCreate(suggestion) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(Theme.Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func create() {
        let trimmed = LogBook.clean(name)
        guard !trimmed.isEmpty else { return }
        guard onCreate(trimmed) else { return }
        name = ""
    }
}

// MARK: - Sidebar

/// Tabs under their group headings, archived ones folded away at the bottom.
private struct LogSidebar: View {
    @Environment(\.modelContext) private var context
    let tabs: [LogTab]
    @Binding var selection: UUID?

    @State private var isCreating = false
    @State private var showsArchived = false

    // Rename, regroup and delete are asked for from context menus and answered
    // in alerts and sheets owned here.
    @State private var renaming: LogTab?
    @State private var renameText = ""
    @State private var regrouping: LogTab?
    @State private var newGroupText = ""
    @State private var renamingGroup: String?
    @State private var groupText = ""
    @State private var deleting: LogTab?
    @State private var error: String?

    private var sections: [LogSection] { LogBook.sections(tabs) }
    private var archived: [LogTab] { LogBook.archived(tabs) }
    private var groups: [String] { LogBook.knownGroups(tabs) }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.tabs) { tab in
                            row(tab).tag(tab.id)
                        }
                        .onMove { source, destination in
                            perform { try LogBook.reorder(section.tabs, fromOffsets: source,
                                                          toOffset: destination, in: context) }
                        }
                    } header: {
                        if !section.group.isEmpty {
                            Text(section.group)
                                .contextMenu {
                                    Button("Rename Group…") {
                                        groupText = section.group
                                        renamingGroup = section.group
                                    }
                                    Button("Ungroup Tabs") {
                                        perform { try LogBook.renameGroup(section.group, to: "", in: context) }
                                    }
                                }
                        }
                    }
                }

                if !archived.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showsArchived) {
                            ForEach(archived) { tab in
                                row(tab).tag(tab.id)
                            }
                        } label: {
                            Text("Archived (\(archived.count))")
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        .accessibilityIdentifier("log.archived")
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("log.tabs")

            Divider()

            Button {
                isCreating = true
            } label: {
                Label("New Tab", systemImage: "plus")
                    .font(Theme.Font.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .accessibilityIdentifier("log.newTab")
            .popover(isPresented: $isCreating, arrowEdge: .top) {
                LogTabCreator(groups: groups) { name, group in
                    do {
                        if let tab = try LogBook.createTab(name: name, group: group, in: context) {
                            selection = tab.id
                        }
                        isCreating = false
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
        .alert("Rename Tab", isPresented: present($renaming)) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let tab = renaming { perform { try LogBook.rename(tab, to: renameText, in: context) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Group", isPresented: present($regrouping)) {
            TextField("Group name", text: $newGroupText)
            Button("Move") {
                if let tab = regrouping {
                    perform { try LogBook.move(tab, toGroup: newGroupText, in: context) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Groups are headings in this list. They don't change anything else.")
        }
        .alert("Rename Group", isPresented: present($renamingGroup)) {
            TextField("Group name", text: $groupText)
            Button("Rename") {
                if let old = renamingGroup {
                    perform { try LogBook.renameGroup(old, to: groupText, in: context) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't save", isPresented: present($error)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .sheet(item: $deleting) { tab in
            DestructiveConfirmation(
                title: "Delete “\(tab.name)”?",
                message: deleteMessage(for: tab),
                phrase: "delete",
                confirmLabel: "Delete Tab",
                onConfirm: {
                    if selection == tab.id { selection = nil }
                    perform { try LogBook.delete(tab, in: context) }
                    deleting = nil
                },
                onCancel: { deleting = nil }
            )
        }
    }

    private func deleteMessage(for tab: LogTab) -> String {
        let count = tab.entries.count
        let entries = count == 1 ? "its 1 entry" : "all \(count) of its entries"
        let archive = tab.isArchived ? "" : " To hide it but keep its history, archive it instead."
        return count == 0
            ? "The tab will be removed.\(archive)"
            : "The tab and \(entries) will be removed.\(archive)"
    }

    private func row(_ tab: LogTab) -> some View {
        HStack(spacing: Theme.Space.s) {
            Circle()
                .fill(tab.color)
                .frame(width: 8, height: 8)
            Text(tab.name)
                .lineLimit(1)
                .foregroundStyle(tab.isArchived ? Theme.secondaryLabel : Theme.label)
            Spacer(minLength: Theme.Space.xs)
            if let last = LogBook.lastLogged(tab) {
                Text(shortDate(last))
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("log.tab.\(tab.name)")
        .contextMenu { menu(for: tab) }
    }

    @ViewBuilder
    private func menu(for tab: LogTab) -> some View {
        Button("Rename…") {
            renameText = tab.name
            renaming = tab
        }
        Menu("Colour") {
            ForEach(CategoryPalette.swatches) { swatch in
                Button {
                    perform { try LogBook.setColor(tab, slot: swatch.slot, in: context) }
                } label: {
                    if swatch.slot == tab.colorSlot {
                        Label(swatch.name, systemImage: "checkmark")
                    } else {
                        Text(swatch.name)
                    }
                }
            }
        }
        if !tab.isArchived {
            Menu("Move to Group") {
                Button("No Group") {
                    perform { try LogBook.move(tab, toGroup: "", in: context) }
                }
                .disabled(tab.group.isEmpty)
                if !groups.isEmpty { Divider() }
                ForEach(groups, id: \.self) { group in
                    Button(group) {
                        perform { try LogBook.move(tab, toGroup: group, in: context) }
                    }
                    .disabled(group == tab.group)
                }
                Divider()
                Button("New Group…") {
                    newGroupText = ""
                    regrouping = tab
                }
            }
        }
        Divider()
        Button(tab.isArchived ? "Unarchive" : "Archive") {
            perform { try LogBook.setArchived(tab, !tab.isArchived, in: context) }
        }
        Button("Delete…", role: .destructive) { deleting = tab }
    }

    private func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return Format.timeOfDay(date) }
        return Format.dayTitle(date)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }

    /// An alert driven by an optional: shown while it holds something, and
    /// cleared when the alert goes away.
    private func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// Name and optional group for a new tab.
private struct LogTabCreator: View {
    let groups: [String]
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var group = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New tab")
                .font(.system(size: 13, weight: .semibold))
            TextField("Name — a course, a paper, a client…", text: $name)
                .accessibilityIdentifier("log.newTab.name")
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack(spacing: Theme.Space.s) {
                TextField("Group (optional)", text: $group)
                    .accessibilityIdentifier("log.newTab.group")
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                if !groups.isEmpty {
                    Menu {
                        ForEach(groups, id: \.self) { existing in
                            Button(existing) { group = existing }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Use an existing group")
                }
            }
            Text("Groups are only headings, like Research. Leave it empty for none.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Create", action: create)
                    .accessibilityIdentifier("log.newTab.create")
                    .keyboardShortcut(.defaultAction)
                    .disabled(LogBook.clean(name).isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
    }

    private func create() {
        guard !LogBook.clean(name).isEmpty else { return }
        onCreate(name, group)
    }
}

// MARK: - A tab

/// Where you stopped, the next entry, and everything before it.
private struct LogTabDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    let tab: LogTab
    @Binding var draft: LogDraft
    let onStartSession: () -> Void

    @State private var savedFlash = false
    @State private var copiedFlash = false
    @State private var saveError: String?
    @State private var editing: LogEntry?
    @State private var pendingDelete: LogEntry?

    /// The running session, when it was started for this tab — a new entry
    /// written now is about it.
    private var linkedSession: WorkSession? {
        guard let session = model.activeSession, session.logTabID == tab.id else { return nil }
        return session
    }

    var body: some View {
        let history = LogBook.history(for: tab)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header(entryCount: history.count)
                if tab.isArchived {
                    archivedBanner
                }
                ResumeCard(tab: tab)
                if !tab.isArchived {
                    composer
                }
                historySection(history)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editing) { entry in
            LogEntryEditor(entry: entry)
        }
        .confirmationDialog("Delete this entry?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { entry in
            Button("Delete Entry", role: .destructive) {
                do {
                    try LogBook.delete(entry, in: context)
                } catch {
                    saveError = "Not deleted: \(error.localizedDescription)"
                }
                pendingDelete = nil
            }
        } message: { entry in
            Text("From \(Format.logStamp(entry.recordedAt)). This cannot be undone.")
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: Header

    private func header(entryCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                if !tab.group.isEmpty {
                    Text(tab.group)
                        .font(Theme.Font.sectionHeader)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.tertiaryLabel)
                }
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(tab.color).frame(width: 10, height: 10)
                    Text(tab.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Space.m)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(LogBook.plainText(for: tab.entries), forType: .string)
                flash(.copiedFlash)
            } label: {
                Label(copiedFlash ? "Copied" : "Copy as Text",
                      systemImage: copiedFlash ? "checkmark" : "doc.on.doc")
            }
            .accessibilityIdentifier("log.copy")
            .disabled(entryCount == 0)
            .help("Copies every entry, newest first, in the same layout as your Google Doc")

            if !tab.isArchived {
                Button(action: onStartSession) {
                    Label("Start Session", systemImage: "play.fill")
                }
                .accessibilityIdentifier("log.startSession")
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(Theme.onAccent)
                .disabled(model.activeSession != nil)
                .help(model.activeSession != nil ? "A session is already running" : "Start a session for this tab")
            }
        }
    }

    private var archivedBanner: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "archivebox")
            Text("Archived. Its history is kept; it's hidden from the session and menu bar pickers.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Unarchive") {
                do { try LogBook.setArchived(tab, false, in: context) }
                catch { saveError = "Not saved: \(error.localizedDescription)" }
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.secondaryLabel)
        .padding(Theme.Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            sectionTitle("New entry")
            LogEntryFields(
                resumePoint: $draft.resumePoint,
                done: $draft.done,
                focusOnAppear: false,
                onSubmit: save
            )
            HStack(spacing: Theme.Space.s) {
                if let linkedSession {
                    Label("Linked to “\(linkedSession.title)”", systemImage: "timer")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                if savedFlash {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                        .accessibilityIdentifier("log.saved")
                }
                Button("Save Entry", action: save)
                    .accessibilityIdentifier("log.save")
                    .disabled(!draft.hasText)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    private func save() {
        guard draft.hasText else { return }
        do {
            guard try model.saveLogDraft(draft, session: linkedSession) != nil else {
                saveError = "Choose an active tab before saving. Your text has been kept."
                return
            }
            draft.clearText()
            saveError = nil
            flash(.savedFlash)
        } catch {
            // The text stays in the fields, so nothing typed is lost.
            saveError = "Not saved: \(error.localizedDescription)"
        }
    }

    // MARK: History

    @ViewBuilder
    private func historySection(_ history: [LogEntry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("History")
                Text(history.count == 1 ? "1 entry" : "\(history.count) entries")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            if history.isEmpty {
                Text("Entries appear here, newest first.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .padding(.vertical, Theme.Space.s)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        LogEntryRow(
                            entry: entry,
                            onEdit: { editing = entry },
                            onDelete: { pendingDelete = entry }
                        )
                    }
                }
                .accessibilityIdentifier("log.history")
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.sectionHeader)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.tertiaryLabel)
    }

    private enum Flash { case savedFlash, copiedFlash }

    /// Shows a brief confirmation, then fades it.
    private func flash(_ which: Flash) {
        set(which, true, animation: .easeOut(duration: 0.15))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            set(which, false, animation: .easeIn(duration: 0.3))
        }
    }

    private func set(_ which: Flash, _ value: Bool, animation: Animation) {
        withAnimation(animation) {
            switch which {
            case .savedFlash: savedFlash = value
            case .copiedFlash: copiedFlash = value
            }
        }
    }
}

/// One entry in a tab's history.
private struct LogEntryRow: View {
    let entry: LogEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                Text(Format.logStamp(entry.recordedAt))
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(Theme.label)
                if let worked = entry.workedSeconds, worked >= 60 {
                    meta("· \(Format.compact(worked))")
                }
                if let title = entry.sessionTitle, !title.isEmpty {
                    meta("· \(title)").lineLimit(1)
                }
                if entry.editedAt != nil {
                    meta("· edited")
                }
                Spacer(minLength: Theme.Space.s)
                HStack(spacing: Theme.Space.xs) {
                    Button("Edit", action: onEdit)
                        .accessibilityIdentifier("log.entry.edit")
                    Button("Delete", role: .destructive, action: onDelete)
                        .accessibilityIdentifier("log.entry.delete")
                }
                .buttonStyle(.link)
                .font(Theme.Font.caption)
                .opacity(isHovering ? 1 : 0)
            }
            if entry.hasResumePoint {
                field("Resume point", entry.resumePoint)
            }
            if entry.hasDone {
                field("Done", entry.done)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.horizontal, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .fill(isHovering ? Theme.surface : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Copy as Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(LogBook.plainText(for: entry), forType: .string)
            }
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
        .accessibilityIdentifier("log.entry")
    }

    private func meta(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.tertiaryLabel)
    }

    private func field(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.tertiaryLabel)
                .frame(width: 84, alignment: .leading)
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
