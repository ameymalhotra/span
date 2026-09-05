import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var notificationsEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Timer end reminders", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            guard enabled else { return }
                            Task { notificationsEnabled = await NotificationService.requestAuthorization() }
                        }
                    Text("Get a reminder when a timed session ends, even when the app is in the background.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your data") {
                    LabeledContent("Storage", value: "Only on this iPhone")
                    Text("Accounts, cloud sync, activity context, and health integrations can be added later without changing your session history.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await updateNotificationStatus() }
        }
    }

    private func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
