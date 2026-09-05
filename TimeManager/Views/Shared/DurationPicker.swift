import SwiftUI

/// Common session lengths, plus any length the user wants.
struct DurationPicker: View {
    @Binding var minutes: Int
    /// Shown under the field so the number has a sense of scale.
    var showsSummary = true

    private static let presets = [30, 60, 90, 120]
    private static let range = 1...600

    @State private var isCustom = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 2) {
                ForEach(Self.presets, id: \.self) { preset in
                    // Formatted rather than raw minutes, so 120 reads as "2h".
                    segment(label: Format.compact(TimeInterval(preset * 60)),
                            selected: !isCustom && minutes == preset) {
                        isCustom = false
                        minutes = preset
                    }
                }
                segment(label: "Custom", selected: isCustom) {
                    isCustom = true
                    draft = "\(minutes)"
                }
            }
            .padding(2)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))

            if isCustom {
                HStack(spacing: Theme.Space.s) {
                    TextField("Minutes", text: $draft)
                        .accessibilityIdentifier("duration.customMinutes")
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onChange(of: draft) { _, new in commit(new) }
                    Stepper("", value: Binding(
                        get: { minutes },
                        set: { minutes = clamp($0); draft = "\(minutes)" }
                    ), in: Self.range, step: 5)
                    .labelsHidden()
                    Text("minutes")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer(minLength: 0)
                }
            }

            if showsSummary {
                Text(Format.compact(TimeInterval(minutes * 60)))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .onAppear {
            // A length that is not one of the presets is by definition custom,
            // so reopening keeps whatever was chosen last time.
            isCustom = !Self.presets.contains(minutes)
            draft = "\(minutes)"
        }
    }

    private func segment(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(selected ? Theme.label : Theme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.raised)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("duration.\(label)")
    }

    /// Keeps a half-typed value usable: an empty or nonsense field leaves the
    /// last good number in place rather than snapping to zero as you delete.
    private func commit(_ text: String) {
        let digits = text.filter(\.isNumber)
        if digits != text { draft = digits; return }
        guard let value = Int(digits) else { return }
        minutes = clamp(value)
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }
}
