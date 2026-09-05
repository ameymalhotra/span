import SwiftUI

struct SettingsScene: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            TrackingSettings()
                .tabItem { Label("Tracking", systemImage: "record.circle") }
            HUDSettings()
                .tabItem { Label("HUD", systemImage: "rectangle.topthird.inset.filled") }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("dailyFocusTargetMinutes") private var target = 300
    @State private var notificationsEnabled = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $target, in: 30...960, step: 30) {
                    LabeledContent("Daily focus target",
                                   value: Format.compact(TimeInterval(target * 60)))
                }
                Text("Drives the “percent of target” readout in the HUD and status bar.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Section("Notifications") {
                Toggle("Remind me when a session ends", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task { notificationsEnabled = await NotificationService.requestAuthorization() }
                    }
            }
            Section("Your data") {
                LabeledContent("Storage", value: "On this Mac only")
                Text("Sessions, entries and tracked activity stay in Application Support. No account, no sync, nothing leaves the machine.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .formStyle(.grouped)
        .task {
            notificationsEnabled = await NotificationService.isAuthorized()
        }
    }
}

private struct TrackingSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Track application activity", isOn: Binding(
                    get: { !model.tracker.isPaused },
                    set: { model.tracker.isPaused = !$0 }
                ))
                Text("Records which app is frontmost and when you step away, so the timeline can show where the day actually went.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            Section("Window titles") {
                LabeledContent("Accessibility access") {
                    Label(
                        model.accessibility.isTrusted ? "Granted" : "Not granted",
                        systemImage: model.accessibility.isTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(model.accessibility.isTrusted ? Color.green : .orange)
                }
                // Titles are an enhancement, never a prerequisite — tracking
                // records the app either way, so this is presented as optional
                // rather than as a blocking permission wall.
                Text("Optional. With access, a timeline block can also show the document or page that was open — otherwise it shows the app alone.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                HStack {
                    Button("Request Access") { model.accessibility.request() }
                        .disabled(model.accessibility.isTrusted)
                    Button("Open System Settings") { model.accessibility.openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // macOS posts nothing when the switch is flipped, so the pane polls
            // while it is on screen.
            while !Task.isCancelled {
                model.accessibility.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct HUDSettings: View {
    @AppStorage("hud.visible") private var isVisible = true

    var body: some View {
        Form {
            Section {
                Toggle("Show the floating HUD", isOn: $isVisible)
                Text("A small always-on-top readout below the menu bar. Clicking it never takes focus from the app you are working in, and it can be dragged anywhere along the top of the screen.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .formStyle(.grouped)
    }
}
