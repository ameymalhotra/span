import Foundation
import UserNotifications

enum NotificationService {

    /// Set by the test harness. Scheduling real notifications from a test run
    /// would prompt for authorisation and leave pending requests behind.
    static let testingEnvironmentKey = "SPAN_TESTING"

    static var isTesting: Bool {
        ProcessInfo.processInfo.environment[testingEnvironmentKey] != nil
    }

    static func requestAuthorization() async -> Bool {
        guard !isTesting else { return false }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Whether the user has already granted permission, so settings can show
    /// the real state instead of an optimistic toggle.
    static func isAuthorized() async -> Bool {
        guard !isTesting else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    static func scheduleEndReminder(for session: WorkSession) {
        guard !isTesting else { return }
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
        guard !isTesting else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [session.id.uuidString])
    }
}
