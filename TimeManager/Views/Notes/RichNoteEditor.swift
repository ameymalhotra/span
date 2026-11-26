import AppKit
import SwiftUI

/// Uses the macOS text system so selection, undo, spelling and rich paste work
/// on macOS 14 too. The buffer is shared; selection belongs to each text view.
@MainActor
@Observable
final class NoteFormatting {
    weak var textView: NSTextView?

    func bold() { toggle(.boldFontMask) }
    func italic() { toggle(.italicFontMask) }

    private func toggle(_ trait: NSFontTraitMask) {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        let range = view.selectedRange()
        let manager = NSFontManager.shared
        let current = view.typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
        let removing = manager.traits(of: current).contains(trait)
        func converted(_ font: NSFont) -> NSFont {
            removing ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
        }
        if range.length == 0 { view.typingAttributes[.font] = converted(current) }
        else if let storage = view.textStorage {
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, run, _ in
                text.addAttribute(.font, value: converted(value as? NSFont ?? current), range: run)
            }
            Self.replace(in: view, range: range, with: text, selection: range)
        }
    }

    func heading(_ heading: Bool) {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        let selection = view.selectedRange()
        let range = (view.string as NSString).paragraphRange(for: selection)
        let font = heading ? NSFont.systemFont(ofSize: 20, weight: .semibold) : NSFont.systemFont(ofSize: 14)
        if range.length == 0 {
            view.typingAttributes[.font] = font
        } else if let storage = view.textStorage {
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
            Self.replace(in: view, range: range, with: text, selection: selection)
        }
    }

    func list(numbered: Bool) {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        let range = (view.string as NSString).paragraphRange(for: view.selectedRange())
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: numbered ? .decimal : .disc, options: 0)]
        style.headIndent = 24
        if range.length == 0 { view.typingAttributes[.paragraphStyle] = style }
        else if let storage = view.textStorage {
            let selection = view.selectedRange()
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
            Self.replace(in: view, range: range, with: text, selection: selection)
        }
    }

    func checklist() {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        let range = (view.string as NSString).paragraphRange(for: view.selectedRange())
        guard let storage = view.textStorage else { return }
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        if text.string.hasPrefix("☐ ") { text.replaceCharacters(in: NSRange(location: 0, length: 1), with: "☑") }
        else if text.string.hasPrefix("☑ ") { text.replaceCharacters(in: NSRange(location: 0, length: 1), with: "☐") }
        else {
            text.insert(NSAttributedString(string: "☐ ", attributes: view.typingAttributes), at: 0)
        }
        let style = NSMutableParagraphStyle()
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        let insertion = NSRange(location: range.location + text.length, length: 0)
        Self.replace(in: view, range: range, with: text, selection: insertion)
    }

    func link(_ url: URL) {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        let range = view.selectedRange()
        if range.length == 0 {
            let text = NSAttributedString(string: url.absoluteString, attributes: [.link: url, .font: NSFont.systemFont(ofSize: 14)])
            Self.replace(in: view, range: range, with: text,
                         selection: NSRange(location: range.location + text.length, length: 0))
        } else if let storage = view.textStorage {
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            text.addAttribute(.link, value: url, range: NSRange(location: 0, length: text.length))
            Self.replace(in: view, range: range, with: text, selection: range)
        }
    }

    /// insertText adapts replacement fonts to the current typing size. Direct
    /// storage edits preserve heading sizes; explicitly register their inverse
    /// so the standard Edit → Undo command still works.
    private static func replace(in view: NSTextView, range: NSRange,
                                with text: NSAttributedString, selection: NSRange) {
        guard let storage = view.textStorage,
              view.shouldChangeText(in: range, replacementString: text.string) else { return }
        let before = storage.attributedSubstring(from: range)
        let previousSelection = view.selectedRange()
        view.undoManager?.registerUndo(withTarget: view) { target in
            MainActor.assumeIsolated {
                replace(in: target, range: NSRange(location: range.location, length: text.length),
                        with: before, selection: previousSelection)
            }
        }
        storage.replaceCharacters(in: range, with: text)
        view.didChangeText()
        view.setSelectedRange(selection)
    }
}

private final class NotebookTextView: NSTextView {
    override func insertNewline(_ sender: Any?) {
        let paragraph = (string as NSString).paragraphRange(for: selectedRange())
        let text = (string as NSString).substring(with: paragraph)
        super.insertNewline(sender)
        if text.hasPrefix("☐ ") || text.hasPrefix("☑ ") {
            insertText("☐ ", replacementRange: selectedRange())
        }
    }
}

struct RichNoteEditor: NSViewRepresentable {
    let document: NoteDocument
    let editing: NoteEditingCoordinator
    let formatting: NoteFormatting
    let isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = NotebookTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.usesFindBar = true
        view.isRichText = true
        view.importsGraphics = false
        view.allowsImageEditing = false
        view.isAutomaticLinkDetectionEnabled = true
        view.isContinuousSpellCheckingEnabled = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.textColor = .textColor
        view.font = .systemFont(ofSize: 14)
        view.textContainerInset = NSSize(width: 24, height: 18)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityIdentifier("notes.body")
        view.setAccessibilityLabel("Note contents")
        scroll.documentView = view
        view.delegate = context.coordinator
        formatting.textView = view
        context.coordinator.load(document.richText, into: view)
        view.setSelectedRange(NSRange(location: min(document.selection.location, view.string.utf16.count), length: 0))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.scrollOffset))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        formatting.textView = view
        view.isEditable = isEditable
        // Own keystrokes have already changed the view. Only a different
        // window's edits need replacing; autosave never resets the cursor.
        if context.coordinator.lastData != document.richText {
            let selection = view.selectedRange()
            let offset = scroll.contentView.bounds.origin
            view.breakUndoCoalescing()
            view.undoManager?.removeAllActions()
            context.coordinator.load(document.richText, into: view)
            let count = view.string.utf16.count
            view.setSelectedRange(NSRange(location: min(selection.location, count), length: 0))
            scroll.contentView.scroll(to: offset)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let view = scroll.documentView as? NSTextView {
            coordinator.parent.document.selection = view.selectedRange()
            coordinator.parent.document.scrollOffset = scroll.contentView.bounds.origin.y
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        var lastData: Data?
        init(_ parent: RichNoteEditor) { self.parent = parent }

        func load(_ data: Data, into view: NSTextView) {
            let text = NSMutableAttributedString(attributedString: NoteBook.attributedText(data))
            // No custom text colours in this editor: semantic colour keeps
            // notes readable when opened in the other appearance.
            text.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(location: 0, length: text.length))
            view.textStorage?.setAttributedString(text)
            if text.length == 0 { view.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.textColor] }
            lastData = data
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, let storage = view.textStorage else { return }
            do {
                let data = try NoteBook.encode(storage)
                lastData = data
                parent.document.richText = data
                parent.document.plainText = storage.string
                parent.editing.changed(parent.document)
            } catch {
                parent.document.error = "Couldn’t format this text: \(error.localizedDescription)"
            }
        }
    }
}
