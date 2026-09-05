import Foundation
import Testing
@testable import Span

@Suite("AppCategorizer")
struct AppCategorizerTests {

    @Test("each rule bucket claims its own apps", arguments: [
        ("com.apple.dt.Xcode", "Building"),
        ("com.microsoft.VSCode", "Building"),
        ("com.googlecode.iterm2", "Building"),
        ("dev.warp.Warp-Stable", "Building"),
        ("com.tinyspeck.slackmacgap", "Talking"),
        ("com.apple.mail", "Talking"),
        ("com.hnc.Discord", "Talking"),
        ("us.zoom.xos", "Meetings"),
        ("com.microsoft.teams2", "Meetings"),
        ("com.apple.Safari", "Browsing"),
        ("com.google.Chrome", "Browsing"),
        ("notion.id", "Reading"),
        ("md.obsidian", "Reading"),
        ("com.figma.Desktop", "Designing"),
        ("com.spotify.client", "Off Task"),
        ("com.apple.finder", "Housekeeping"),
        ("com.apple.systempreferences", "Housekeeping"),
    ])
    func rules(bundleID: String, expected: String) {
        #expect(AppCategorizer.category(forBundleIdentifier: bundleID, appName: "Whatever") == expected)
    }

    @Test("an unrecognised app keeps its own name as the category")
    func unknownFallsBackToName() {
        #expect(AppCategorizer.category(forBundleIdentifier: "com.example.Tempo", appName: "Tempo") == "Tempo")
        #expect(AppCategorizer.category(forBundleIdentifier: "io.example.widget", appName: "Widget") == "Widget")
    }

    @Test("a missing or empty bundle identifier falls back to the name")
    func missingBundleID() {
        #expect(AppCategorizer.category(forBundleIdentifier: nil, appName: "Ledger") == "Ledger")
        #expect(AppCategorizer.category(forBundleIdentifier: "", appName: "Ledger") == "Ledger")
    }

    @Test("matching ignores case")
    func caseInsensitive() {
        #expect(AppCategorizer.category(forBundleIdentifier: "COM.APPLE.DT.XCODE", appName: "X") == "Building")
        #expect(AppCategorizer.category(forBundleIdentifier: "com.TinySpeck.SlackMacGap", appName: "X") == "Talking")
    }

    @Test("an explicit identifier beats a keyword in another category")
    func identifierBeatsKeyword() {
        // Contains "chrome" (Browsing, a keyword) but is listed under Building.
        #expect(AppCategorizer.category(
            forBundleIdentifier: "com.jetbrains.chromeplugin", appName: "X") == "Building")
    }

    // MARK: - Substring collisions

    @Test("Archive Utility is housekeeping, not a browser")
    func archiveUtilityIsNotABrowser() {
        // Its identifier contains "arc"; an explicit identifier rule settles it
        // before any keyword is consulted.
        #expect(AppCategorizer.category(
            forBundleIdentifier: "com.apple.archiveutility", appName: "Archive Utility")
            == "Housekeeping")
    }

    @Test("Arc is recognised by the identifier it actually ships under")
    func arcIsMatched() {
        // Arc is company.thebrowser.Browser — nothing in it says "arc".
        #expect(AppCategorizer.category(
            forBundleIdentifier: "company.thebrowser.Browser", appName: "Arc") == "Browsing")
    }

    @Test("an ordinary word inside an identifier no longer files the app", arguments: [
        ("com.example.Ledger", "Ledger"),          // contains "edge"
        ("com.tvtropes.reader", "Reader"),         // contains "tv"
        ("com.meetup.organiser", "Organiser"),     // contains "meet"
        ("com.banknotes.scanner", "Scanner"),      // contains "notes"
        ("com.thingsmagazine.app", "Things Magazine"), // contains "things"
        ("com.bearblog.writer", "Bear Blog"),      // contains "bear"
        ("com.novastudio.tool", "Nova Studio"),    // contains "nova"
        ("com.craftbeer.finder", "Craft Beer"),    // contains "craft" and "finder"
    ])
    func wordsInsideIdentifiersDoNotMatch(bundleID: String, appName: String) {
        #expect(AppCategorizer.category(forBundleIdentifier: bundleID, appName: appName) == appName)
    }

    @Test("a vendor namespace can be claimed wholesale")
    func namespacePrefixes() {
        #expect(AppCategorizer.category(forBundleIdentifier: "com.jetbrains.intellij", appName: "X") == "Building")
        #expect(AppCategorizer.category(forBundleIdentifier: "com.jetbrains.AppCode", appName: "X") == "Building")
        // The prefix has to end at a component boundary. (Checked with a
        // vendor that is not also a keyword, so only the prefix rule is in
        // play — "jetbrains" is distinctive enough to stand alone as one.)
        #expect(AppCategorizer.category(forBundleIdentifier: "com.seriflabs.affinity", appName: "X") == "Designing")
        #expect(AppCategorizer.category(forBundleIdentifier: "com.seriflabsclone.app", appName: "Clone") == "Clone")
    }

    @Test("an opaque identifier is still caught by a distinctive keyword")
    func keywordFallback() {
        // Cursor ships under a generated ToDesktop identifier.
        #expect(AppCategorizer.category(
            forBundleIdentifier: "com.todesktop.cursor230313", appName: "Cursor") == "Building")
    }

    @Test("the app name is ignored when the bundle identifier is present")
    func nameIsNotConsulted() {
        // "Xcode" as a name, but an identifier that matches nothing.
        #expect(AppCategorizer.category(forBundleIdentifier: "com.example.tool", appName: "Xcode") == "Xcode")
    }
}
