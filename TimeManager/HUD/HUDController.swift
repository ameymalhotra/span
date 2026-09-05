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

    /// -1 means "never dragged", i.e. stay centred.
    private var xFraction: Double {
        get { defaults.object(forKey: Key.xFraction) as? Double ?? -1 }
        set { defaults.set(newValue, forKey: Key.xFraction) }
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
    func reposition() {
        guard let panel, let screen = targetScreen() else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = xFraction >= 0
            ? frame.minX + CGFloat(xFraction) * max(1, frame.width - size.width)
            : frame.midX - size.width / 2
        let y = frame.maxY - size.height - CGFloat(topOffset)
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// Follows whichever display the pointer is on, so the HUD turns up where
    /// the user is looking on a multi-display desk.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    @objc private func screensChanged() { reposition() }

    // Position is stored as a fraction of the visible frame rather than as
    // absolute points, so it survives a resolution or display change.
    func windowDidMove(_ notification: Notification) {
        guard let panel, let screen = targetScreen() else { return }
        let frame = screen.visibleFrame
        xFraction = Double((panel.frame.minX - frame.minX) / max(1, frame.width - panel.frame.width))
        topOffset = Double(frame.maxY - panel.frame.maxY)
    }
}
