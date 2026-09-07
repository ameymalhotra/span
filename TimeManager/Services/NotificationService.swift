import AppKit
import Foundation
import UserNotifications

enum NotificationService {

    /// Set by the test harness. Scheduling real notifications from a test run
    /// would prompt for authorisation and leave pending requests behind.
    static let testingEnvironmentKey = "SPAN_TESTING"

    static var isTesting: Bool {
        ProcessInfo.processInfo.environment[testingEnvironmentKey] != nil
    }

    /// Defaults key for the end-of-session sound. Separate from the banner:
    /// the banner needs the system's permission, the sound does not, and most
    /// people who want one want the other.
    static let soundEnabledKey = "sessionEndSound"

    static var isSoundEnabled: Bool {
        UserDefaults.standard.object(forKey: soundEnabledKey) as? Bool ?? true
    }

    static func requestAuthorization() async -> Bool {
        guard !isTesting else { return false }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Asks once, the first time it could matter.
    ///
    /// Authorisation used to be requested only by the toggle in settings, so
    /// anyone who never opened settings had every end-of-session banner
    /// silently dropped — the reminder was scheduled, and macOS discarded it.
    /// Asking when the first session starts puts the prompt where its purpose
    /// is obvious, and asking only when the status is undetermined means a
    /// refusal is never second-guessed.
    static func requestAuthorizationIfUndetermined() {
        guard !isTesting else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = await requestAuthorization()
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

    @MainActor
    static func scheduleEndReminder(for session: WorkSession) {
        armChime(for: session)
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

    @MainActor
    static func cancelReminder(for session: WorkSession) {
        chime?.cancel()
        chime = nil
        guard !isTesting else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [session.id.uuidString])
    }

    // MARK: - The chime

    /// The in-app half of "time is up".
    ///
    /// The scheduled notification above is the system's to deliver and only
    /// arrives if permission was granted; this is ours and always plays, since
    /// sounding the end is the one thing a timer has to do. Both are armed
    /// together so no caller can reschedule one and forget the other.
    @MainActor private static var chime: Task<Void, Never>?
    /// The session whose end has already been sounded, so the timer below and
    /// the tick backstop cannot announce the same ending twice.
    @MainActor private static var chimedSession: UUID?

    @MainActor
    private static func armChime(for session: WorkSession) {
        chime?.cancel()
        chime = nil
        guard session.status == .active else { return }

        // Re-arming means the end moved — the session was extended, resumed or
        // its planned length edited — so a previous announcement no longer
        // stands for the new ending.
        let remaining = session.remaining()
        if remaining > 0 { chimedSession = nil }

        chime = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0.25, remaining)))
            guard !Task.isCancelled else { return }
            announceEnd(of: session)
        }
    }

    /// Backstop for the timer above: a Mac that slept through the end, or a
    /// session whose length changed by a route that did not reschedule.
    @MainActor
    static func announceEndIfDue(for session: WorkSession?, at date: Date = .now) {
        guard let session, session.status == .active,
              session.remaining(at: date) <= 0 else { return }
        announceEnd(of: session)
    }

    @MainActor
    static func announceEnd(of session: WorkSession) {
        guard session.status == .active, chimedSession != session.id else { return }
        chimedSession = session.id
        guard !isTesting else { return }
        if isSoundEnabled { NSSound(named: "Glass")?.play() }
        // Bounces the Dock icon once. The point of the alert is to reach
        // someone who is looking at a different app.
        NSApp?.requestUserAttention(.informationalRequest)
    }
}
