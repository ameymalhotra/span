import AppKit
import SwiftUI

/// Scrolls the timeline while a drag is held near its top or bottom edge, the
/// way a calendar does when a block is pulled past what is on screen.
///
/// Reaches for the `NSScrollView` behind SwiftUI's `ScrollView` because there
/// is no way to scroll that by a few points from SwiftUI on macOS 14:
/// `ScrollViewProxy` only jumps to anchors.
///
/// A pointer held still sends no drag events, so the gesture cannot notice the
/// day moving under it by itself. Each step reports how far it scrolled, and
/// the drag adds that to where it last saw the pointer until the next event —
/// which, measured in the track's own coordinate space, already includes it.
@MainActor
final class TimelineAutoScroller {

    fileprivate weak var scrollView: NSScrollView?

    private var loop: Task<Void, Never>?
    private var onScroll: ((CGFloat) -> Void)?

    /// How close to an edge the pointer has to be before the day moves.
    private static let edge: CGFloat = 40
    /// Points per step at the very edge. Slower further in, so the pointer
    /// sets the pace.
    private static let topSpeed: CGFloat = 16

    /// Starts following the pointer for the drag in progress. `onScroll` is
    /// handed each step's distance, positive when the day moved later.
    func follow(_ onScroll: @escaping (CGFloat) -> Void) {
        self.onScroll = onScroll
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.step()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        onScroll = nil
    }

    private func step() {
        guard let scrollView, let window = scrollView.window,
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let pointer = clip.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let visible = clip.bounds

        // Measured as "down the day", whichever way the document is flipped.
        let fromTop = clip.isFlipped ? pointer.y - visible.minY : visible.maxY - pointer.y
        let fromBottom = visible.height - fromTop
        let speed: CGFloat
        if fromTop < Self.edge {
            speed = -Self.topSpeed * min(1, (Self.edge - fromTop) / Self.edge)
        } else if fromBottom < Self.edge {
            speed = Self.topSpeed * min(1, (Self.edge - fromBottom) / Self.edge)
        } else {
            return
        }

        let limit = max(0, document.frame.height - visible.height)
        let current = clip.isFlipped ? visible.minY : limit - visible.minY
        let target = min(max(0, current + speed), limit)
        let moved = target - current
        guard moved != 0 else { return }

        clip.scroll(to: NSPoint(x: visible.minX, y: clip.isFlipped ? target : limit - target))
        scrollView.reflectScrolledClipView(clip)
        onScroll?(moved)
    }
}

/// Finds the scroll view the timeline is drawn in, for the auto-scroller.
struct TimelineScrollViewFinder: NSViewRepresentable {
    let scroller: TimelineAutoScroller

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // Not in the hierarchy yet on the first pass.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            scroller.scrollView = view.enclosingScrollView
        }
    }
}

/// Where a drag last saw the pointer, and how far the day has scrolled under
/// it since.
///
/// A class, so that recording either on every event changes nothing a view
/// draws from.
@MainActor
final class DragTracker {
    var translation: CGFloat = 0
    var scrolled: CGFloat = 0

    /// A fresh event: its translation is measured in the track, so it already
    /// includes any scrolling, and the carry starts again.
    func record(_ translation: CGFloat) {
        self.translation = translation
        scrolled = 0
    }

    var total: CGFloat { translation + scrolled }
}

/// The track's coordinate space. Drags are measured in it rather than in
/// their own view's, because the card being dragged moves — and a gesture
/// measured against a view it is moving reads its own movement back as the
/// pointer's, which is what made cards jitter under the cursor.
enum TimelineSpace {
    static let track = "timeline.track"
}
