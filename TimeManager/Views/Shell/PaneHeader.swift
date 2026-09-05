import SwiftUI

/// A pane's title, pinned above its scrolling content.
///
/// Titles used to live inside each pane's ScrollView, which put them under the
/// window's translucent toolbar: the Day heading was clipped to a sliver and
/// the timeline's legend disappeared behind it entirely. A pinned header sits
/// in normal layout, so it cannot be scrolled under or clipped away.
struct PaneHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.m)
    }
}
