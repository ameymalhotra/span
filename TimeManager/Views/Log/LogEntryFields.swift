import SwiftUI

/// The two questions every log entry asks. One view, used by the Log pane, the
/// edit sheet, the review sheet and the menu bar, so the fields read and
/// behave identically wherever an entry is written.
///
/// Return in the first field moves to the second; Return in the second saves.
/// ⌥Return starts a new line in either, for a list of what got done.
struct LogEntryFields: View {
    @Binding var resumePoint: String
    @Binding var done: String
    /// Fewer lines and smaller labels, for the menu bar popover.
    var compact = false
    /// Puts the cursor in the first field when the form appears.
    var focusOnAppear = true
    /// Called by Return in the last field and by ⌘Return in either.
    var onSubmit: (() -> Void)?
    /// Prefix for accessibility identifiers, so each surface can be driven on
    /// its own: `log`, `reflection.log`, `menuBar.log`.
    var identifier = "log"

    private enum Field { case resume, done }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Theme.Space.xs : Theme.Space.s) {
            fieldLabel("Resume point / Things to do")
            TextField("", text: $resumePoint,
                      prompt: Text("Where to pick up next time"), axis: .vertical)
                .accessibilityIdentifier("\(identifier).resumePoint")
                .accessibilityLabel("Resume point / Things to do")
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(compact ? 1...4 : 2...6)
                .focused($focus, equals: .resume)
                .onSubmit { focus = .done }

            fieldLabel("What was done in this session")
                .padding(.top, compact ? 0 : Theme.Space.xs)
            TextField("", text: $done,
                      prompt: Text("Optional"), axis: .vertical)
                .accessibilityIdentifier("\(identifier).done")
                .accessibilityLabel("What was done in this session")
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(compact ? 1...4 : 2...8)
                .focused($focus, equals: .done)
                .onSubmit { onSubmit?() }

            if !compact {
                Text("Return to move on · ⌥Return for a new line · ⌘Return to save")
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .background {
            // ⌘Return saves from either field.
            Button("") { onSubmit?() }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            guard focusOnAppear else { return }
            // A beat later: focus set during the first layout pass of a sheet
            // or popover is dropped.
            Task { @MainActor in focus = .resume }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(compact ? Theme.Font.micro : Theme.Font.caption.weight(.medium))
            .foregroundStyle(Theme.secondaryLabel)
    }
}
