import SwiftUI

/// The offer that follows a finished session.
///
/// Shown once the review has been dealt with, because the review is about the
/// session that just ended and this is about the next quarter of an hour — and
/// because a break offered before the review would be answered by dismissing
/// both.
struct BreakPromptView: View {
    let start: (Int) -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Take a break?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text("Step away and Span will sound the end of it. Nothing is recorded while you are gone.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BreakOptions(start: start)

            HStack {
                Spacer()
                Button("Not now", action: decline)
                    .accessibilityIdentifier("break.notNow")
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 360)
    }
}
