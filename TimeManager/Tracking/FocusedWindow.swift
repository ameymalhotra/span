import ApplicationServices
import AppKit

/// Reads the title of an app's focused window through the Accessibility API.
enum FocusedWindow {

    /// Focused window title for `pid`, or nil when Accessibility access is not
    /// granted, the app exposes no AX window, or the window is untitled.
    ///
    /// For browsers this is where tab context comes from: Safari and Chrome
    /// both put the active tab's page title in the window title, so no
    /// browser-specific automation is needed to see which page was open.
    static func title(forProcessIdentifier pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let app = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef
        ) == .success, let title = titleRef as? String else { return nil }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
