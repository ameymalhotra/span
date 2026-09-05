import Foundation
import SwiftData
import SwiftUI

/// The user's own answer to "what kind of work is this app?".
///
/// Built-in rules cover the obvious cases, but only the person doing the work
/// knows whether their browser is research or distraction. A rule here beats
/// the built-in table for that bundle identifier.
@Model
final class AppCategoryRule {
    var bundleIdentifier: String = ""
    /// Kept so the rule can still be shown sensibly if the app is uninstalled.
    var appName: String = ""
    var categoryName: String = ""

    init(bundleIdentifier: String, appName: String, categoryName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.categoryName = categoryName
    }
}

extension AppCategoryRule {
    /// Files an app under a category, replacing any existing rule for it.
    @MainActor
    static func assign(_ category: String, bundleIdentifier: String,
                       appName: String, in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppCategoryRule>())) ?? []
        if let rule = existing.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            rule.categoryName = category
        } else {
            context.insert(AppCategoryRule(bundleIdentifier: bundleIdentifier,
                                           appName: appName, categoryName: category))
        }
        try? context.save()
        ModelStack.loadAppRules(in: context)
    }
}

/// A group on the timeline — a category, or a single app — with the apps that
/// make it up.
struct LegendEntry: Identifiable {
    struct AppShare: Identifiable {
        let bundleIdentifier: String
        let name: String
        let duration: TimeInterval
        var id: String { bundleIdentifier }
    }

    let name: String
    let duration: TimeInterval
    let fraction: Double
    let apps: [AppShare]

    var id: String { name }
    var color: Color { CategoryPalette.color(for: name) }
}

/// Whether the timeline shows each app separately or rolls them into
/// categories.
enum TimelineGrouping: String, CaseIterable, Identifiable {
    case category, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: "By category"
        case .app: "By app"
        }
    }

    var detail: String {
        switch self {
        case .category: "Safari and Chrome both count as Browsing."
        case .app: "Safari and Chrome are listed separately."
        }
    }
}
