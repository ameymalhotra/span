import SwiftData
import SwiftUI

/// Contents of the menu bar item's popover.
struct MenuBarPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @Query(sort: \LogTab.sortIndex) private var logTabs: [LogTab]
    @AppStorage("log.lastTabID") private var lastLogTabRaw = ""
    @State private var isLogging = false
    @State private var savedTo: String?
    @State private var logError: String?

    private var hasLogTabs: Bool { logTabs.contains { !$0.isArchived } }

    /// The tab you last worked on or logged to, for the idle reminder.
    private var lastLogTab: LogTab? {
        LogBook.activeTab(id: UUID(uuidString: lastLogTabRaw), in: logTabs)
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if model.isOnBreak {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On a break")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.breakClock + " left")
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Button(model.sessionPausedForBreak ? "Back to work" : "End break") {
                    model.endBreak()
                }
                .accessibilityIdentifier("menuBar.endBreak")
                .buttonStyle(.borderedProminent)
                .tint(Theme.rest)
                .foregroundStyle(.white)
            } else if let session = model.activeSession {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(model.sessionClock + " remaining")
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                HStack(spacing: Theme.Space.s) {
                    if session.status == .paused {
                        Button("Resume") { model.resumeSession() }
                            .accessibilityIdentifier("menuBar.resume")
                    } else {
                        Button("Pause") { model.pauseSession() }
                            .accessibilityIdentifier("menuBar.pause")
                    }
                    Button("+5m") { model.extendSession(byMinutes: 5) }
                        .accessibilityIdentifier("menuBar.extend")
                        .help("Add five minutes to the planned time")
                    Button("Finish") {
                        model.finishSession()
                        // The review sheet lives in the main window, which may
                        // not even be open from here.
                        openMainWindow()
                    }
                        .accessibilityIdentifier("menuBar.finish")
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No session running")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryLabel)
                    // Where you said you'd pick up, so the menu bar answers
                    // "where was I" before a session is even started.
                    if let tab = lastLogTab, let next = LogBook.latestResumePoint(for: tab) {
                        Text("\(tab.name): \(next.resumePoint)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.tertiaryLabel)
                            .lineLimit(2)
                            .accessibilityIdentifier("menuBar.nextStep")
                    }
                }
            }

            Divider()

            LabeledContent("Focus today", value: model.focusTodayText)
            LabeledContent("Of target", value: model.percentOfTargetText)
            LabeledContent("Now", value: model.tracker.isPaused
                           ? "Tracking paused"
                           : (model.tracker.isIdle ? "Away" : model.tracker.currentAppName))

            Divider()

            if hasLogTabs {
                if isLogging {
                    logForm(draft: $model.menuBarLogDraft)
                } else {
                    HStack(spacing: Theme.Space.s) {
                        Button {
                            beginLogging()
                        } label: {
                            Label("Log Entry…", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("menuBar.logEntry")
                        if let savedTo {
                            Label("Saved to \(savedTo)", systemImage: "checkmark.circle.fill")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                                .accessibilityIdentifier("menuBar.logSaved")
                        }
                    }
                }
                Divider()
            }

            Button("Open Span") {
                openMainWindow()
            }
            Button("Quit") { NSApp.terminate(nil) }
                .accessibilityIdentifier("menuBar.quit")
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.l)
        .onAppear {
            model.beginFastUpdates()
            // A half-written entry reopens where it was left.
            if model.menuBarLogDraft.hasText { isLogging = true }
        }
        .onDisappear { model.endFastUpdates() }
    }

    // MARK: - Log entry

    /// Writes a handoff from anywhere, with or without a timer running.
    private func logForm(draft: Binding<LogDraft>) -> some View {
        let tab = LogBook.activeTab(id: draft.wrappedValue.tabID, in: logTabs)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Log entry")
                .font(.system(size: 13, weight: .semibold))
            LogTabPicker(selection: draft.tabID, noneLabel: "Choose a tab",
                         identifier: "menuBar.logTab")
            if let tab {
                ResumeCard(tab: tab, compact: true)
            }
            LogEntryFields(
                resumePoint: draft.resumePoint,
                done: draft.done,
                compact: true,
                onSubmit: saveLog,
                identifier: "menuBar.log"
            )
            .disabled(tab == nil)
            if let session = linkedSession(for: tab) {
                Label("Linked to “\(session.title)”", systemImage: "timer")
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .lineLimit(1)
            }
            if let logError {
                Label(logError, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") {
                    model.menuBarLogDraft.clearText()
                    logError = nil
                    isLogging = false
                }
                .accessibilityIdentifier("menuBar.logCancel")
                Spacer()
                Button("Save", action: saveLog)
                    .accessibilityIdentifier("menuBar.logSave")
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
                    .disabled(tab == nil || !draft.wrappedValue.hasText)
            }
        }
    }

    /// The running session, when it is for this tab — the entry is about it.
    /// Otherwise none: an entry written away from the timer has no duration.
    private func linkedSession(for tab: LogTab?) -> WorkSession? {
        guard let tab, let session = model.activeSession, session.logTabID == tab.id else { return nil }
        return session
    }

    private func beginLogging() {
        savedTo = nil
        logError = nil
        if LogBook.activeTab(id: model.menuBarLogDraft.tabID, in: logTabs) == nil {
            // The running session's tab, else the last one used.
            let running = LogBook.activeTab(id: model.activeSession?.logTabID, in: logTabs)
            model.menuBarLogDraft.tabID = (running ?? lastLogTab)?.id
        }
        isLogging = true
    }

    private func saveLog() {
        let draft = model.menuBarLogDraft
        guard let tab = LogBook.activeTab(id: draft.tabID, in: logTabs), draft.hasText else { return }
        do {
            guard try LogBook.save(draft, session: linkedSession(for: tab), in: context) != nil else { return }
            lastLogTabRaw = tab.id.uuidString
            model.menuBarLogDraft.clearText()
            logError = nil
            isLogging = false
            savedTo = tab.name
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if savedTo == tab.name { savedTo = nil }
            }
        } catch {
            logError = "Not saved: \(error.localizedDescription)"
        }
    }

    /// Fronts the main window, which is where sheets are presented and may be
    /// closed while the menu bar item is still around.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is HUDPanel) }?.makeKeyAndOrderFront(nil)
    }
}
