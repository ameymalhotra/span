import SwiftData
import SwiftUI

/// Preferences, in the window rather than behind ⌘, — the daily target drives
/// numbers on three other screens, so it needs to be somewhere you can find it.
struct SettingsPaneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @AppStorage("dailyFocusTargetMinutes") private var targetMinutes = 300
    @AppStorage("defaultSessionMinutes") private var defaultSessionMinutes = 60
    @AppStorage("idleThresholdMinutes") private var idleThresholdMinutes = 5
    @AppStorage("hud.visible") private var hudVisible = true
    @AppStorage("userName") private var userName = ""
    @AppStorage("personalNote") private var personalNote = ""
    @State private var notificationsEnabled = false

    private static let targets = [120, 180, 240, 300, 360, 420, 480]

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Settings")
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                you
                goals
                categoriesSection
                tracking
                alerts
                data
            }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        .background(Theme.canvas)
        .task {
            notificationsEnabled = await NotificationService.isAuthorized()
            while !Task.isCancelled {
                // macOS posts nothing when Accessibility is granted, so this
                // pane polls while it is on screen.
                model.accessibility.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Sections

    private var you: some View {
        section("You") {
            row("Name", detail: "Used for the greeting on the Focus pane. Never leaves this Mac.") {
                TextField("Your name", text: $userName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            Divider()

            stackedRow("Your line",
                       detail: "Shown on the Focus pane and when you start a session. A reason, a reminder, something you are working towards.") {
                TextField("Finish the thing before starting the next one.",
                          text: $personalNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
            }
        }
    }


    private var categoriesSection: some View {
        section("Categories") {
            CategoryManager()
        }
    }


    private var goals: some View {
        section("Focus goals") {
            row("Daily target",
                detail: "Drives the target percentage in the status bar, the HUD and Insights.") {
                Picker("", selection: $targetMinutes) {
                    ForEach(Self.targets, id: \.self) { minutes in
                        Text(Format.compact(TimeInterval(minutes * 60))).tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            Divider()

            stackedRow("Default session", detail: "Pre-selected when you start a new session.") {
                DurationPicker(minutes: $defaultSessionMinutes, showsSummary: false)
            }
        }
    }

    private var tracking: some View {
        section("Tracking") {
            row("Track application activity",
                detail: "Records which app is frontmost and when you step away.") {
                Toggle("", isOn: Binding(
                    get: { !model.tracker.isPaused },
                    set: { model.tracker.isPaused = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            row("Away after", detail: "How long without input counts as a break.") {
                Picker("", selection: $idleThresholdMinutes) {
                    ForEach([2, 3, 5, 10, 15], id: \.self) { Text("\($0)m").tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            Divider()

            row("Window titles",
                detail: model.accessibility.isTrusted
                    ? "Granted — blocks can show the document or page that was open."
                    : "Optional. Without it a block shows the app name alone.") {
                if model.accessibility.isTrusted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(Theme.Font.caption)
                } else {
                    Button("Grant…") { model.accessibility.request() }
                }
            }
            if !model.accessibility.isTrusted {
                Button("Open System Settings") { model.accessibility.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(Theme.Font.caption)
            }
        }
    }

    private var alerts: some View {
        section("Alerts and the HUD") {
            row("Session end reminder", detail: "Notifies you when a timed session runs out.") {
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task { notificationsEnabled = await NotificationService.requestAuthorization() }
                    }
            }

            Divider()

            row("Floating HUD",
                detail: "A small always-on-top readout below the menu bar. Clicking it never takes focus from the app you are in.") {
                Toggle("", isOn: $hudVisible)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var data: some View {
        section("Your data") {
            row("Storage", detail: "Kept in one file on this Mac. No account, no sync, nothing leaves the machine.") {
                EmptyView()
            }
        }
    }

    // MARK: - Chrome

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title)
                .font(Theme.Font.sectionHeader)
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryLabel)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                content()
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    /// Label on the left, a compact control on the right.
    private func row(_ title: String, detail: String,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            label(title, detail)
                // Priority and a floor together: without them a wide trailing
                // control takes the space it asks for and the text collapses.
                .frame(minWidth: 160, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: Theme.Space.s)
            control().fixedSize()
        }
    }

    /// Label above, control beneath — for controls too wide to sit beside text.
    private func stackedRow(_ title: String, detail: String,
                            @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            label(title, detail)
            control().frame(maxWidth: 330, alignment: .leading)
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Font.body)
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
