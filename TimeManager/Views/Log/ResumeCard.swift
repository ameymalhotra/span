import SwiftUI

/// "Pick up here": the last thing you told yourself to do next in a tab.
///
/// Shown at the top of a tab in the Log pane, on the start sheet once a tab is
/// chosen, and in the menu bar — the same card everywhere, so the answer to
/// "where was I" always looks the same.
struct ResumeCard: View {
    let tab: LogTab
    /// Tighter, for the start sheet and the menu bar.
    var compact = false

    var body: some View {
        let entry = LogBook.latestResumePoint(for: tab)
        VStack(alignment: .leading, spacing: compact ? 2 : Theme.Space.xs) {
            Text("Pick up here")
                .font(compact ? Theme.Font.micro : Theme.Font.sectionHeader)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.tertiaryLabel)

            if let entry {
                Text(entry.resumePoint)
                    .font(compact ? Theme.Font.body.weight(.medium)
                                  : .system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.label)
                    .lineLimit(compact ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("log.resumeCard.text")
                HStack(spacing: Theme.Space.xs) {
                    Text(Format.logRelative(entry.recordedAt))
                    if let worked = entry.workedSeconds, worked >= 60 {
                        Text("·")
                        Text(Format.compact(worked))
                    }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
            } else {
                Text("Nothing logged yet — add where you'll pick up.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityIdentifier("log.resumeCard.empty")
            }
        }
        .padding(.vertical, compact ? Theme.Space.s : Theme.Space.m)
        .padding(.leading, (compact ? Theme.Space.s : Theme.Space.m) + 3)
        .padding(.trailing, compact ? Theme.Space.s : Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tab.color.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.card,
                                   bottomLeadingRadius: Theme.Radius.card)
                .fill(tab.color)
                .frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }
}
