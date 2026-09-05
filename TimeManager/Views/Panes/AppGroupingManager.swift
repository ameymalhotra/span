import SwiftData
import SwiftUI

/// Decides which category each tracked app is filed under.
///
/// The list grows on its own — every app you touch appears here — so it is
/// built to stay usable at a hundred entries: searchable, filterable to the
/// ones still unassigned, and bounded in height so it cannot swamp the rest of
/// Settings.
struct AppGroupingManager: View {
    @Environment(\.modelContext) private var context

    @AppStorage("timelineGrouping") private var groupingRaw = TimelineGrouping.category.rawValue

    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var activity: [ActivityRecord]

    @State private var search = ""
    @State private var showsUnassignedOnly = false

    private struct SeenApp: Identifiable {
        let bundleIdentifier: String
        let name: String
        let total: TimeInterval
        var id: String { bundleIdentifier }
    }

    /// Apps seen, busiest first.
    private var apps: [SeenApp] {
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        for record in activity where !record.isIdle {
            guard let bundle = record.bundleIdentifier, !bundle.isEmpty else { continue }
            let existing = totals[bundle]
            totals[bundle] = (record.appName, (existing?.seconds ?? 0) + record.duration)
        }
        return totals
            .map { SeenApp(bundleIdentifier: $0.key, name: $0.value.name, total: $0.value.seconds) }
            .sorted { $0.total > $1.total }
    }

    private var visible: [SeenApp] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return apps.filter { app in
            if showsUnassignedOnly,
               !AppCategorizer.isUngrouped(bundleIdentifier: app.bundleIdentifier, appName: app.name) {
                return false
            }
            guard !query.isEmpty else { return true }
            return app.name.lowercased().contains(query)
                || app.bundleIdentifier.lowercased().contains(query)
        }
    }

    private var unassignedCount: Int {
        apps.filter {
            AppCategorizer.isUngrouped(bundleIdentifier: $0.bundleIdentifier, appName: $0.name)
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Picker("", selection: $groupingRaw) {
                ForEach(TimelineGrouping.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(TimelineGrouping(rawValue: groupingRaw)?.detail ?? "")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)

            if apps.isEmpty {
                Text("Apps appear here once tracking has seen them.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .padding(.vertical, Theme.Space.s)
            } else {
                Divider()
                controls
                list
                Text("Changing an app's category re-files the time it has already recorded, not just what comes next.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryLabel)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 0.5))

            // Worth its own filter: with many apps the ones still carrying their
            // own name are the only ones needing a decision.
            Toggle(isOn: $showsUnassignedOnly) {
                Text("Unassigned\(unassignedCount > 0 ? " (\(unassignedCount))" : "")")
                    .font(Theme.Font.caption)
            }
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            Text(showsUnassignedOnly && search.isEmpty
                 ? "Every app you have used is filed under a category."
                 : "No app matches “\(search)”.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.tertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Space.m)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                // Bounded and scrolled past a handful, so a long list cannot
                // push the rest of Settings off the page.
                ScrollView {
                    VStack(spacing: Theme.Space.xs) {
                        ForEach(visible) { app in
                            row(app)
                        }
                    }
                    .padding(.trailing, Theme.Space.xs)
                }
                .frame(maxHeight: visible.count > 6 ? 260 : .infinity)
                .fixedSize(horizontal: false, vertical: visible.count <= 6)

                Text(countLabel)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
    }

    private var countLabel: String {
        if visible.count == apps.count {
            return "\(apps.count) app\(apps.count == 1 ? "" : "s") tracked"
        }
        return "\(visible.count) of \(apps.count) apps"
    }

    private func row(_ app: SeenApp) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Theme.Font.body)
                    .lineLimit(1)
                Text(Format.compact(app.total))
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CategoryPicker(selection: binding(for: app))
                .frame(width: 186)
        }
    }

    /// Reads through to the resolved category so the picker shows what is
    /// actually in effect, whether that came from a rule or the built-in table.
    private func binding(for app: SeenApp) -> Binding<String> {
        Binding(
            get: {
                AppCategorizer.category(forBundleIdentifier: app.bundleIdentifier,
                                        appName: app.name)
            },
            set: { newValue in
                AppCategoryRule.assign(newValue, bundleIdentifier: app.bundleIdentifier,
                                       appName: app.name, in: context)
            }
        )
    }
}
