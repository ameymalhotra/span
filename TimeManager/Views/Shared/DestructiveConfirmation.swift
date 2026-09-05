import SwiftUI

/// A confirmation for something that cannot be undone.
///
/// A one-click dialog is too easy to dismiss by reflex when the action erases
/// work permanently, so this asks the user to type a phrase. The typing is not
/// ceremony — it is the pause that makes the reading happen.
struct DestructiveConfirmation: View {
    let title: String
    let message: String
    /// What the user must type. Matched case-insensitively, trimmed.
    let phrase: String
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var typed = ""
    @FocusState private var isFocused: Bool

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(phrase) == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This cannot be undone.")
                        .font(Theme.Font.body.weight(.medium))
                        .foregroundStyle(Theme.label)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Type \(phrase) to confirm")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                TextField("", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { if matches { onConfirm() } }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmLabel, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!matches)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .onAppear { isFocused = true }
    }
}
