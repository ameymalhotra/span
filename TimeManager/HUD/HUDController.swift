import AppKit
import SwiftUI

/// Shows, positions and persists the floating HUD.
@MainActor
final class HUDController: NSObject, NSWindowDelegate {

    private var panel: HUDPanel?
    private let model: AppModel

    private let defaults = UserDefaults.standard
    private enum Key {
        static let xFraction = "hud.xFraction"
        static let topOffset = "hud.topOffset"
    }

    /// -1 means "never dragged", i.e. stay centred. Anything outside 0...1 is
    /// treated as never dragged: a stored fraction beyond the screen puts the
    /// panel somewhere the user cannot see or reach it, and the only way back
    /// would be editing defaults by hand.
    private var xFraction: Double {
        get {
            guard let stored = defaults.object(forKey: Key.xFraction) as? Double,
                  (0...1).contains(stored) else { return -1 }
            return stored
        }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.xFraction) }
    }
    private var topOffset: Double {
        get { defaults.object(forKey: Key.topOffset) as? Double ?? 8 }
        set { defaults.set(newValue, forKey: Key.topOffset) }
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        let panel = panel ?? makePanel()
        reposition()
        // orderFrontRegardless, not makeKeyAndOrderFront: showing the HUD must
        // not activate the app.
        panel.orderFrontRegardless()
        model.beginFastUpdates()
    }

    func hide() {
        guard panel != nil else { return }
        panel?.orderOut(nil)
        model.endFastUpdates()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func resetPosition() {
        xFraction = -1
        topOffset = 8
        reposition()
    }

    private func makePanel() -> HUDPanel {
        let panel = HUDPanel(rootView: HUDPillView(controller: self).environment(model))
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// Anchored to `visibleFrame`, which already excludes the menu bar, so the
    /// offset is measured from just below it.
    ///
    /// `screen` defaults to whichever display the pointer is on. A caller that
    /// is only re-anchoring the pill where it already sits passes its current
    /// display instead — otherwise the pill would hop to the pointer every time
    /// its contents changed width.
    func reposition(on screen: NSScreen? = nil) {
        guard let panel, let screen = screen ?? targetScreen() else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = xFraction >= 0
            ? frame.minX + CGFloat(xFraction) * max(1, frame.width - size.width)
            : frame.midX - size.width / 2
        let y = frame.maxY - size.height - CGFloat(topOffset)

        // Clamped to the visible frame regardless of what was stored, so a
        // stale position — from another display, or a resolution change —
        // cannot strand the panel off-screen.
        let clampedX = min(max(x, frame.minX), max(frame.minX, frame.maxX - size.width))
        let clampedY = min(max(y, frame.minY), max(frame.minY, frame.maxY - size.height))
        panel.setFrameOrigin(NSPoint(x: clampedX.rounded(), y: clampedY.rounded()))
    }

    /// Follows whichever display the pointer is on, so the HUD turns up where
    /// the user is looking on a multi-display desk.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    @objc private func screensChanged() { reposition() }

    /// The pill's width follows its contents, and AppKit grows a window from its
    /// bottom-left corner. Re-anchoring on every resize keeps the top edge
    /// pinned under the menu bar and a centred pill centred.
    func windowDidResize(_ notification: Notification) {
        reposition(on: panel?.screen)
    }

    // Position is stored as a fraction of the visible frame rather than as
    // absolute points, so it survives a resolution or display change.
    func windowDidMove(_ notification: Notification) {
        guard let panel, let screen = targetScreen() else { return }
        let frame = screen.visibleFrame
        // A panel as wide as the screen makes the denominator vanish, and the
        // fraction explodes; guard it rather than storing nonsense.
        let travel = frame.width - panel.frame.width
        guard travel > 1 else { return }
        xFraction = Double((panel.frame.minX - frame.minX) / travel)
        topOffset = Double(max(0, min(frame.height - panel.frame.height,
                                      frame.maxY - panel.frame.maxY)))
    }
}
