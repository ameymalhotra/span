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

    static func category(forBundleIdentifier bundleID: String?, appName: String) -> String {
        guard let bundleID, !bundleID.isEmpty else { return appName }
        let haystack = bundleID.lowercased()
        for rule in rules where rule.needles.contains(where: haystack.contains) {
            return rule.category
        }
        return appName
    }
}
