import SwiftUI

/// A session or a hand-made entry, drawn as a card in the wide lane.
struct CardBlockView: View {
    let block: TimelineBlock
    let height: CGFloat

    /// Text is disclosed by available height rather than truncated into an
    /// unreadable sliver.
    private var showsTitle: Bool { height >= 18 }
    private var showsDetail: Bool { height >= 38 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // The solid leading bar keeps the category legible even when the
            // block is too short for any text at all.
            Rectangle()
                .fill(block.color)
                .frame(width: 3)

            if showsTitle {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Space.xs) {
                        Text(block.title.isEmpty ? "Click to name" : block.title)
                            .font(Theme.Font.blockTitle)
                            .foregroundStyle(block.title.isEmpty ? Theme.tertiaryLabel : Theme.label)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Space.xs)
                        if let rating = block.focusRating {
                            FocusPips(rating: rating)
                        }
                    }
                    if showsDetail {
                        Text("\(Format.timeOfDay(block.start)) · \(Format.compact(block.duration))")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.block))
        .overlay(border)
        .help(tooltip)
    }

    @ViewBuilder private var background: some View {
        switch block.kind {
        case .entry:
            // Entries sit on a material rather than a tint, which together with
            // the dashed border distinguishes "you wrote this" from a session's
            // solid, recorded authority.
            RoundedRectangle(cornerRadius: Theme.Radius.block).fill(.regularMaterial)
        default:
            RoundedRectangle(cornerRadius: Theme.Radius.block).fill(block.color.opacity(0.16))
        }
    }

    @ViewBuilder private var border: some View {
        if block.kind == .entry {
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .strokeBorder(block.color.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .strokeBorder(block.color.opacity(0.28), lineWidth: 0.5)
        }
    }

    private var tooltip: String {
        "\(block.title) · \(Format.compact(block.duration))\n"
            + "\(Format.timeOfDay(block.start)) – \(Format.timeOfDay(block.end))"
    }
}

/// The focus rating from the post-session review, as five small pips.
struct FocusPips: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...5, id: \.self) { pip in
                Circle()
                    .fill(pip <= rating ? Theme.accent : Theme.tertiaryLabel.opacity(0.35))
                    .frame(width: 3, height: 3)
            }
        }
        .help("Focus \(rating) of 5")
    }
}

/// Popover shown when a block is clicked.
struct TimelineBlockDetail: View {
    let block: TimelineBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Circle().fill(block.color).frame(width: 8, height: 8)
                Text(block.title)
                    .font(.headline)
                Spacer(minLength: Theme.Space.l)
                Text(kindLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            if let subtitle = block.subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(3)
            }

            Divider()

            LabeledContent("Span",
                           value: "\(Format.timeOfDay(block.start)) – \(Format.timeOfDay(block.end))")
            LabeledContent("Duration", value: Format.compact(block.duration))
            if let category = block.category {
                LabeledContent("Category", value: category)
            }
            if let rating = block.focusRating {
                LabeledContent("Focus", value: "\(rating) of 5")
            }
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.l)
        .frame(width: 280)
    }

    private var kindLabel: String {
        switch block.kind {
        case .session: "Session"
        case .entry: "Entry"
        case .activity: "Tracked"
        case .idle: "Away"
        }
    }
}
