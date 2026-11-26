import AppKit
import SwiftUI

/// Lets a failed save stop a note window from closing. Forward the scene's
/// original delegate methods so SwiftUI still manages the window lifecycle.
struct NoteWindowGuard: NSViewRepresentable {
    let keepOnTop: Bool
    let editing: NoteEditingCoordinator
    let noteID: UUID

    func makeCoordinator() -> Delegate { Delegate(editing: editing, noteID: noteID) }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let delegate = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = keepOnTop ? .floating : .normal
            if window.delegate !== delegate {
                delegate.original = window.delegate
                delegate.window = window
                window.delegate = delegate
            }
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Delegate) {
        if let window = coordinator.window, window.delegate === coordinator {
            window.delegate = coordinator.original
        }
    }

    @MainActor
    final class Delegate: NSObject, NSWindowDelegate {
        // NSObject forwarding is nonisolated; AppKit invokes it on the UI thread.
        nonisolated(unsafe) weak var original: (any NSWindowDelegate)?
        weak var window: NSWindow?
        let editing: NoteEditingCoordinator
        let noteID: UUID
        init(editing: NoteEditingCoordinator, noteID: UUID) {
            self.editing = editing
            self.noteID = noteID
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            do { try editing.flush(noteID) }
            catch {
                let alert = NSAlert()
                alert.messageText = "Your note hasn’t been saved"
                alert.informativeText = error.localizedDescription + " Retry saving or copy your text before closing."
                alert.runModal()
                return false
            }
            return original?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            return original?.responds(to: selector) ?? false
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            let target = original?.responds(to: selector) == true ? original : nil
            return target ?? super.forwardingTarget(for: selector)
        }
    }
}
