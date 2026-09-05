import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Whether the user has already granted permission, so settings can show
    /// the real state instead of an optimistic toggle.
    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    static func scheduleEndReminder(for session: WorkSession) {
        let seconds = max(1, session.remaining())
        let content = UNMutableNotificationContent()
        content.title = "Your work time is over"
        content.body = "\(session.title) is ready for a quick reflection."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: session.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelReminder(for session: WorkSession) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [session.id.uuidString])
    }
}
