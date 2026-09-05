import SwiftData
import SwiftUI

/// Decides which category each tracked app is filed under.
///
/// Listed from what has actually been seen rather than from a catalogue of
/// every app installed: the only apps worth a decision are the ones you use.
struct AppGroupingManager: View {
    @Environment(\.modelContext) private var context

    @AppStorage("timelineGrouping") private var groupingRaw = TimelineGrouping.category.rawValue

    @Query(sort: \ActivityRecord.startedAt, order: .reverse) private var activity: [ActivityRecord]
    @Query private var rules: [AppCategoryRule]

    private struct SeenApp: Identifiable {
        let bundleIdentifier: String
        let name: String
        let total: TimeInterval
        var id: String { bundleIdentifier }
    }

    /// Apps seen recently, busiest first.
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
                ForEach(apps.prefix(20)) { app in
                    row(app)
                }
                Text("Changing an app's category re-files the time it has already recorded, not just what comes next.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .padding(.top, Theme.Space.xs)
            }
        }
    }

    private func row(_ app: SeenApp) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Theme.Font.body)
                Text(Format.compact(app.total))
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            Spacer(minLength: Theme.Space.s)
            CategoryPicker(selection: binding(for: app))
                .frame(minWidth: 130, maxWidth: 190)
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
