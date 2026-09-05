import SwiftData
import SwiftUI

/// Preferences, in the window rather than behind ⌘, — the daily target drives
/// numbers on three other screens, so it needs to be somewhere you can find it.
struct SettingsPaneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @AppStorage("dailyFocusTargetMinutes") private var targetMinutes = 300
    @AppStorage("defaultSessionMinutes") private var defaultSessionMinutes = 50
    @AppStorage("idleThresholdMinutes") private var idleThresholdMinutes = 5
    @AppStorage("hud.visible") private var hudVisible = true
    @State private var notificationsEnabled = false

    private static let targets = [120, 180, 240, 300, 360, 420, 480]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                goals
                categoriesSection
                tracking
                alerts
                data
            }
            .padding(Theme.Space.xl)
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

            row("Default session", detail: "Pre-selected when you start a new session.") {
                DurationPicker(minutes: $defaultSessionMinutes, showsSummary: false)
                    .frame(width: 260)
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
            row("Storage", detail: "~/Library/Application Support/TimeManager. No account, no sync, nothing leaves this Mac.") {
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

    private func row(_ title: String, detail: String,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.m)
            control()
        }
    }
}
