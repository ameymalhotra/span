import AppKit
import SwiftUI

/// Sets a hard minimum size on the hosting window.
///
/// `.windowResizability(.contentMinSize)` with a `.frame(minWidth:)` on the
/// root is meant to do this, but a hierarchy containing `maxWidth: .infinity`
/// reports a smaller minimum than the frame asks for, and the window resizes
/// straight past it. The panes then have to render wider than their slots and
/// the leftmost one is drawn under the sidebar. Constraining the window itself
/// is the only reliable way to stop that.
struct WindowMinimumSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(from: view)
    }

    private func apply(from view: NSView) {
        // The view has no window until after this pass, so the assignment waits
        // for the next runloop turn.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let minimum = NSSize(width: width, height: height)
            guard window.minSize != minimum else { return }
            window.minSize = minimum
            // A window already smaller than the new minimum is grown to it,
            // rather than being left in a state it can no longer be resized to.
            var frame = window.frame
            if frame.width < width || frame.height < height {
                frame.size.width = max(frame.width, width)
                frame.size.height = max(frame.height, height)
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
