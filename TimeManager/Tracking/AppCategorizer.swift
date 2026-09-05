import Foundation

/// Sorts applications into the same free-text categories the user already
/// types into sessions, so auto-tracked time and hand-started sessions land in
/// one shared vocabulary and the day's breakdown adds up across both.
enum AppCategorizer {

    /// Matched against the lowercased bundle identifier, first hit wins.
    private static let rules: [(needles: [String], category: String)] = [
        (["xcode", "vscode", "visual-studio", "iterm", "terminal", "ghostty",
          "warp", "jetbrains", "sublime", "cursor", "zed", "nova"], "Building"),
        (["slack", "mail", "messages", "discord", "telegram", "whatsapp",
          "spark", "superhuman"], "Talking"),
        (["zoom", "webex", "facetime", "teams", "meet", "around"], "Meetings"),
        (["safari", "chrome", "arc", "firefox", "edge", "brave"], "Browsing"),
        (["notion", "obsidian", "bear", "craft", "notes", "things", "reminders",
          "preview", "books"], "Reading"),
        (["figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator",
          "blender"], "Designing"),
        (["spotify", "music", "netflix", "tv", "podcasts", "steam", "vlc"], "Off Task"),
        (["finder", "systempreferences", "systemsettings", "activitymonitor",
          "installer", "archiveutility"], "Housekeeping"),
    ]

    /// The user's own rules, refreshed from the store when they change. Views
    /// resolve categories while drawing, so this cannot be a fetch.
    nonisolated(unsafe) private static var overrides: [String: String] = [:]

    static func updateOverrides(_ rules: [AppCategoryRule]) {
        overrides = Dictionary(
            rules.map { ($0.bundleIdentifier.lowercased(), $0.categoryName) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A user rule wins over the built-in table; an app matching neither keeps
    /// its own name, which is more honest than filing it under something wrong.
    static func category(forBundleIdentifier bundleID: String?, appName: String) -> String {
        guard let bundleID, !bundleID.isEmpty else { return appName }
        let key = bundleID.lowercased()
        if let assigned = overrides[key], !assigned.isEmpty { return assigned }
        for rule in rules where rule.needles.contains(where: key.contains) {
            return rule.category
        }
        return appName
    }

    /// True when nothing but the app's own name is filing it.
    static func isUngrouped(bundleIdentifier: String?, appName: String) -> Bool {
        category(forBundleIdentifier: bundleIdentifier, appName: appName) == appName
    }
}
