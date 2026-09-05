import SwiftUI

/// Small drawn illustrations for the guide.
///
/// Diagrams rather than screenshots on purpose: they are built from the same
/// theme tokens as the real interface, so they stay correct when the palette
/// changes, they render properly in both appearances, and they cannot quietly
/// go out of date the way a captured image does.
enum GuideDiagram {

    /// The two tracks: activity rail on the left, sessions and blocks beside it.
    static var timeline: some View {
        Frame(height: 132) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 22) {
                    ForEach(["9", "10", "11"], id: \.self) { hour in
                        Text(hour)
                            .font(Theme.Font.micro)
                            .foregroundStyle(Theme.tertiaryLabel)
                    }
                }
                .frame(width: 14)

                // Rail: one continuous band.
                VStack(spacing: 0) {
                    railSegment(CategoryPalette.color(slot: 3), 34)
                    railSegment(Theme.tertiaryLabel.opacity(0.28), 12)
                    railSegment(CategoryPalette.color(slot: 1), 22)
                    railSegment(CategoryPalette.color(slot: 0), 30)
                }
                .frame(width: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 0.5)
                            Spacer(minLength: 0)
                        }
                    }
                    block(title: "Write the report", slot: 4, y: 0, height: 46)
                    block(title: "Standup", slot: 2, y: 58, height: 22, dashed: true)
                    Rectangle()
                        .fill(Theme.now)
                        .frame(height: 1)
                        .offset(y: 96)
                }
            }
            .padding(10)
        }
    }

    /// Dragging empty space to sweep out a block.
    static var dragToCreate: some View {
        Frame(height: 108) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 26) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    }
                }
                RoundedRectangle(cornerRadius: Theme.Radius.block)
                    .fill(Theme.accent.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.block)
                            .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        Text("2:10 PM – 2:45 PM")
                            .font(Theme.Font.micro)
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .padding(5)
                    }
                    .frame(height: 52)
                    .offset(y: 14)
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .offset(x: 6, y: 52)
            }
            .padding(12)
        }
    }

    /// The HUD capsule.
    static var hud: some View {
        Frame(height: 82) {
            HStack(spacing: 0) {
                stat("03:43", "TIME SINCE", "LAST BREAK", tint: .white.opacity(0.92))
                stat("2h 10m", "FOCUS", "TODAY", tint: Color(rgbHex: 0x2FD3BC))
                stat("43%", "PERCENT", "OF TARGET", tint: .white.opacity(0.92))
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 10)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(Color(rgbHex: 0x1E1E20).opacity(0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pieces

    private static func railSegment(_ colour: Color, _ height: CGFloat) -> some View {
        Rectangle().fill(colour).frame(height: height)
    }

    private static func block(title: String, slot: Int, y: CGFloat,
                              height: CGFloat, dashed: Bool = false) -> some View {
        let colour = CategoryPalette.color(slot: slot)
        return HStack(spacing: 0) {
            Rectangle().fill(colour).frame(width: 3)
            Text(title)
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .padding(.horizontal, 5)
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .fill(dashed ? Color.clear : colour.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.block)
                .strokeBorder(colour.opacity(dashed ? 0.6 : 0.28),
                              style: StrokeStyle(lineWidth: dashed ? 1 : 0.5,
                                                 dash: dashed ? [4, 3] : []))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.block))
        .offset(y: y)
    }

    private static func stat(_ value: String, _ top: String, _ bottom: String,
                             tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: -1) {
                Text(top)
                Text(bottom)
            }
            .font(.system(size: 7, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.45))
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    /// Shared surround so every diagram reads as an illustration rather than as
    /// part of the interface.
    private struct Frame<Content: View>: View {
        let height: CGFloat
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
        }
    }
}
