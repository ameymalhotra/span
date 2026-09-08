import SwiftUI

/// The quick break lengths, plus one you type.
///
/// Shared by the Focus pane and the offer that follows a finished session, so
/// taking a break is the same gesture wherever you are when you decide to.
struct BreakOptions: View {
    /// Called with the chosen length in minutes.
    let start: (Int) -> Void
    var presets: [Int] = [5, 10, 15]

    /// Long enough for a lunch break, short enough that a typo cannot start a
    /// break that outlives the day.
    private static let longest = 240

    @State private var isChoosing = false
    @State private var draft = "20"

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(presets, id: \.self) { minutes in
                Button("\(minutes)m") { start(minutes) }
                    .accessibilityIdentifier("break.\(minutes)")
                    .help("Take a \(minutes)-minute break")
            }
            Button("Custom…") { isChoosing = true }
                .accessibilityIdentifier("break.custom")
                .popover(isPresented: $isChoosing, arrowEdge: .bottom) { custom }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var custom: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Minutes", text: $draft)
                .accessibilityIdentifier("break.customMinutes")
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .onSubmit(commit)
            Text("minutes")
                .foregroundStyle(Theme.secondaryLabel)
            Button("Start", action: commit)
                .accessibilityIdentifier("break.startCustom")
                .keyboardShortcut(.defaultAction)
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.m)
    }

    /// Typed rather than stepped, and Return starts it: a break is decided in
    /// the second before you stand up.
    private func commit() {
        let digits = draft.filter(\.isNumber)
        guard let minutes = Int(digits), minutes > 0 else { return }
        isChoosing = false
        start(min(minutes, Self.longest))
    }
}
