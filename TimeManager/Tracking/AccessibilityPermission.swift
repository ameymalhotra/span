import ApplicationServices
import AppKit
import SwiftUI

/// Wraps the Accessibility (AX) trust check that window-title capture depends on.
///
/// Without it the tracker still records which app was frontmost — it just can't
/// see what was open inside it. Tracking is therefore never gated on this being
/// granted; titles are an enhancement, not a requirement.
@Observable
@MainActor
final class AccessibilityPermission {

    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// Re-reads the current trust state. macOS gives no notification when the
    /// user flips the switch in System Settings, so this is polled while the
    /// settings pane is open and re-checked when the app is reactivated.
    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Triggers the system prompt. Only shows once per app signature — after
    /// the user has answered, macOS silently returns the stored answer, which
    /// is why `openSystemSettings()` exists as the follow-up path.
    func request() {
        // Spelled literally rather than via `kAXTrustedCheckOptionPrompt`: that
        // symbol is an unannotated global mutable `Unmanaged<CFString>!`, which
        // Swift 6 rejects as concurrency-unsafe. The key string itself is API.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
