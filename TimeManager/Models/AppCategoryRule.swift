import Foundation
import SwiftData

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
