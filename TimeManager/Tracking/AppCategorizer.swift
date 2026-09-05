import Foundation

/// Sorts applications into the same free-text categories the user already
/// types into sessions, so auto-tracked time and hand-started sessions land in
/// one shared vocabulary and the day's breakdown adds up across both.
enum AppCategorizer {

    /// Bundle identifiers, matched exactly — or as a prefix when the entry ends
    /// in a dot, for vendors that ship a family of apps under one namespace.
    ///
    /// Checked before `keywordRules`, and checked in full, so a specific
    /// identifier always beats a keyword guess: Archive Utility is
    /// housekeeping even though its identifier happens to contain "arc".
    private static let identifierRules: [(ids: [String], category: String)] = [
        (["com.apple.dt.xcode", "com.microsoft.vscode", "com.vscodium",
          "com.googlecode.iterm2", "com.apple.terminal", "com.mitchellh.ghostty",
          "dev.warp.warp-stable", "dev.zed.zed", "com.panic.nova",
          "com.jetbrains.", "com.sublimetext."], "Building"),
        (["com.tinyspeck.slackmacgap", "com.apple.mail", "com.apple.mobilesms",
          "com.hnc.discord", "org.telegram.desktop", "net.whatsapp.whatsapp",
          "com.readdle.smartemail-mac", "com.superhuman.electron"], "Talking"),
        (["us.zoom.xos", "com.cisco.webexmeetingsapp", "com.apple.facetime",
          "com.microsoft.teams", "com.microsoft.teams2"], "Meetings"),
        (["com.apple.safari", "com.google.chrome", "company.thebrowser.browser",
          "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.browser"], "Browsing"),
        (["notion.id", "md.obsidian", "net.shinyfrog.bear", "com.lukilabs.lukiapp",
          "com.apple.notes", "com.culturedcode.thingsmac", "com.apple.reminders",
          "com.apple.preview", "com.apple.ibooksx"], "Reading"),
        (["com.figma.desktop", "com.bohemiancoding.sketch3", "com.adobe.photoshop",
          "com.adobe.illustrator", "org.blenderfoundation.blender",
          "com.seriflabs.", "com.pixelmatorteam."], "Designing"),
        (["com.spotify.client", "com.apple.music", "com.netflix.netflix",
          "com.apple.tv", "com.apple.podcasts", "com.valvesoftware.steam",
          "org.videolan.vlc"], "Off Task"),
        (["com.apple.finder", "com.apple.systempreferences", "com.apple.systemsettings",
          "com.apple.activitymonitor", "com.apple.installer",
          "com.apple.archiveutility"], "Housekeeping"),
    ]

    /// Distinctive words, matched anywhere in the identifier, for apps whose
    /// identifier is opaque or that ship under many of them.
    ///
    /// Every needle here is long enough and specific enough to stand alone.
    /// Short ones do not work: "arc" filed Archive Utility as a browser, "edge"
    /// filed anything with "ledger" in its name, and "tv" and "meet" matched
    /// halfway through unrelated words. A needle that is also an English
    /// fragment belongs in `identifierRules` as a full identifier instead.
    private static let keywordRules: [(needles: [String], category: String)] = [
        (["xcode", "vscode", "visual-studio", "iterm", "jetbrains", "sublime",
          "ghostty", "cursor", "zedindustries"], "Building"),
        (["slack", "discord", "telegram", "whatsapp", "superhuman"], "Talking"),
        (["zoom.us", "webex", "facetime", "microsoft.teams", "bluejeans"], "Meetings"),
        (["safari", "chrome", "firefox", "chromium", "vivaldi"], "Browsing"),
        (["notion", "obsidian", "readwise"], "Reading"),
        (["figma", "sketch", "photoshop", "illustrator", "pixelmator",
          "blender"], "Designing"),
        (["spotify", "netflix", "podcasts", "steam"], "Off Task"),
        (["systempreferences", "systemsettings", "activitymonitor",
          "archiveutility"], "Housekeeping"),
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
        for rule in identifierRules where rule.ids.contains(where: { matches(key, $0) }) {
            return rule.category
        }
        for rule in keywordRules where rule.needles.contains(where: key.contains) {
            return rule.category
        }
        return appName
    }

    /// An entry ending in a dot matches a whole namespace; anything else has to
    /// be the identifier itself.
    private static func matches(_ key: String, _ identifier: String) -> Bool {
        identifier.hasSuffix(".") ? key.hasPrefix(identifier) : key == identifier
    }

    /// True when nothing but the app's own name is filing it.
    static func isUngrouped(bundleIdentifier: String?, appName: String) -> Bool {
        category(forBundleIdentifier: bundleIdentifier, appName: appName) == appName
    }
}
