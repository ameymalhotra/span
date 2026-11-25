import SwiftData
import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss

    /// Categories already used, newest first, so the free-text field gains the
    /// convenience of a picker without the model needing a category entity.
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]

    @AppStorage("personalNote") private var personalNote = ""
    @State private var title = ""
    @State private var category = "Deep Work"
    @AppStorage("defaultSessionMinutes") private var minutes = 60

    @Query(sort: \LogTab.sortIndex) private var logTabs: [LogTab]
    /// The tab the last session was started for, offered again by default.
    @AppStorage("log.lastTabID") private var lastLogTabRaw = ""
    @State private var logTabID: UUID?
    /// The title the sheet filled in from a tab's name, so picking another tab
    /// can replace it — but never something the user typed.
    @State private var prefilledTitle: String?

    /// The tab to open with, when the sheet was opened from that tab in the Log.
    var preselectedLogTabID: UUID? = nil
    let onStart: (String, String, Int, UUID?) -> Void

    private var logTab: LogTab? { LogBook.activeTab(id: logTabID, in: logTabs) }
    private var hasLogTabs: Bool { logTabs.contains { !$0.isArchived } }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var knownCategories: [String] {
        var seen: [String] = []
        for session in sessions {
            let name = session.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.append(name)
            if seen.count == 8 { break }
        }
        return seen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("New session")
                    .font(.system(size: 15, weight: .semibold))
                if !personalNote.isEmpty {
                    Text(personalNote)
                        .font(Theme.Font.caption)
                        .italic()
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.l)

            Divider()

            Form {
                if hasLogTabs {
                    Section("Picking up") {
                        // Only a choice made here adopts the tab's name and
                        // category; the remembered default leaves both alone.
                        LogTabPicker(selection: Binding(
                            get: { logTabID },
                            set: { new in
                                guard new != logTabID else { return }
                                logTabID = new
                                adopt(LogBook.activeTab(id: new, in: logTabs))
                            }
                        ), noneLabel: "No log tab", identifier: "startSession.logTab")
                        if let logTab {
                            ResumeCard(tab: logTab, compact: true)
                        }
                    }
                }

                Section("What are you working on?") {
                    // `prompt`, not the label: inside a grouped Form the
                    // first string is the row's *label*, which macOS lays out
                    // on the left and pushes the field itself to the trailing
                    // edge — leaving the caret parked at the far right of the
                    // row while the example text sat where a placeholder looks
                    // like it should be.
                    TextField(text: $title, prompt: Text("e.g. Rebuild the timeline")) {
                        Text("Session title")
                    }
                    .accessibilityIdentifier("startSession.title")
                    .labelsHidden()
                    CategoryPicker(selection: $category)
                    HStack(spacing: Theme.Space.xs) {
                        Circle()
                            .fill(CategoryPalette.color(for: category))
                            .frame(width: 8, height: 8)
                        Text("This category's colour on the timeline")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                Section("How long?") {
                    DurationPicker(minutes: $minutes)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("startSession.cancel")
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") {
                    let tabID = logTab?.id
                    onStart(trimmedTitle, category.trimmingCharacters(in: .whitespacesAndNewlines),
                            minutes, tabID)
                    dismiss()
                }
                .accessibilityIdentifier("startSession.start")
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
            }
            .padding(Theme.Space.l)
        }
        .frame(width: 420)
        .onAppear {
            if let preselectedLogTabID {
                logTabID = preselectedLogTabID
                adopt(LogBook.activeTab(id: preselectedLogTabID, in: logTabs))
            } else {
                logTabID = LogBook.activeTab(id: UUID(uuidString: lastLogTabRaw), in: logTabs)?.id
            }
        }
    }

    /// Takes what a chosen tab implies: its name as the title while the title
    /// is empty (or still the last tab's name), and the category last used
    /// for it.
    private func adopt(_ tab: LogTab?) {
        if trimmedTitle.isEmpty || trimmedTitle == prefilledTitle {
            title = tab?.name ?? ""
            prefilledTitle = tab?.name
        }
        if let tab, let previous = sessions.first(where: { $0.logTabID == tab.id }) {
            let name = previous.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { category = name }
        }
    }
}
