import CoreGraphics
import Foundation

/// Reports how long the user has been away from the keyboard and mouse.
///
/// Uses `CGEventSource`, which needs no permission — unlike an event tap, it
/// reports only *when* input last happened, never what it was.
enum IdleMonitor {

    /// Seconds since the last keyboard or mouse event anywhere on the system.
    static func idleInterval() -> TimeInterval {
        // `kCGAnyInputEventType` has no Swift constant; it is defined as the
        // all-bits-set event type, which matches keyboard, mouse and tablet input.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// How long the user must be untouched before the span is recorded as a
    /// break. Five minutes is long enough to survive reading a long page, short
    /// enough that stepping away for coffee is not billed as work; adjustable
    /// in Settings because that trade-off is personal.
    static var threshold: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: "idleThresholdMinutes") as? Int ?? 5
        return TimeInterval(max(1, minutes) * 60)
    }

    static var isIdle: Bool { idleInterval() >= threshold }
}
