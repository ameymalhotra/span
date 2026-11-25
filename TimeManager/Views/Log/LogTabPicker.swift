import SwiftData
import SwiftUI

/// Chooses which Log tab something goes to, or none.
///
/// Only active tabs are offered. A selection pointing at an archived or
/// deleted tab is shown — and corrected — as "none", so a remembered choice
/// can never send an entry somewhere the user cannot see.
struct LogTabPicker: View {
    @Binding var selection: UUID?
    var noneLabel = "Don't log"
    var identifier = "log.tabPicker"

    @Query(sort: \LogTab.sortIndex) private var tabs: [LogTab]

    private var selected: LogTab? { LogBook.activeTab(id: selection, in: tabs) }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            // The menu cannot show colours (macOS draws menu images as
            // templates), so the chosen tab's colour sits beside it.
            Circle()
                .fill(selected?.color ?? Theme.hairline)
                .frame(width: 8, height: 8)
            Picker("Log to", selection: Binding(
                get: { selected?.id },
                set: { selection = $0 }
            )) {
                Text(noneLabel).tag(UUID?.none)
                ForEach(LogBook.sections(tabs)) { section in
                    if section.group.isEmpty {
                        tabItems(section.tabs)
                    } else {
                        Section(section.group) { tabItems(section.tabs) }
                    }
                }
            }
            .labelsHidden()
            .accessibilityIdentifier(identifier)
        }
        .onAppear {
            if selection != nil && selected == nil { selection = nil }
        }
        .onChange(of: selected?.id) { _, id in
            // Another window can archive or delete the tab while this form
            // is open. Correct the choice without clearing its typed text.
            if selection != nil && id == nil { selection = nil }
        }
    }

    private func tabItems(_ tabs: [LogTab]) -> some View {
        ForEach(tabs) { tab in
            Text(tab.name).tag(UUID?.some(tab.id))
        }
    }
}
