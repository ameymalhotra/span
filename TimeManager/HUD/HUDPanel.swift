import AppKit
import SwiftUI

/// The window behind the floating pill.
///
/// A non-activating panel: clicking it must never pull focus away from whatever
/// the user is actually working in, which is the whole reason a always-on-top
/// readout is tolerable at all.
final class HUDPanel: NSPanel {

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 40),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above ordinary and floating windows, but below the menu bar itself,
        // which is what the pill tucks under.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
        // The HUD keeps its dark identity in both appearances — it floats over
        // the desktop rather than sitting inside the app's own surfaces.
        appearance = NSAppearance(named: .vibrantDark)

        // A hosting *controller*, not a hosting view: the window then tracks the
        // pill's fitting size, and the pill is only as wide as what it is
        // currently showing (a running session's clock is wider than a day
        // total). In a fixed-size window the capsule would instead stretch to
        // whatever width was guessed here.
        contentViewController = NSHostingController(rootView: AnyView(rootView))
    }

    // Never key, never main: no focus stealing.
    //
    // The consequence is that keyboard events do not reach this panel at all —
    // buttons and menus work, a text field would be inert. The pill is
    // deliberately read-only plus buttons for that reason.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
