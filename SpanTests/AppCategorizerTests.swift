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
        ("company.thebrowser.Browser", "Browsing"),
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
        #expect(AppCategorizer.category(forBundleIdentifier: "com.example.Ledger", appName: "Ledger") == "Ledger")
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

    @Test("the first matching rule wins over a later one")
    func firstRuleWins() {
        // Contains both "cursor" (Building, rule 1) and "notes" (Reading, rule 5).
        #expect(AppCategorizer.category(forBundleIdentifier: "com.cursor.notes", appName: "X") == "Building")
    }

    // MARK: - Substring collisions

    @Test("BUG: Archive Utility files as Browsing because its identifier contains 'arc'")
    func archiveUtilityCollidesWithArc() {
        let category = AppCategorizer.category(
            forBundleIdentifier: "com.apple.archiveutility", appName: "Archive Utility")
        // Housekeeping lists "archiveutility" explicitly, but Browsing's "arc"
        // needle matches first and the rule list is ordered, first hit wins.
        #expect(category == "Browsing")
        #expect(category != "Housekeeping", "Archive Utility should be Housekeeping")
    }

    @Test("BUG: short needles match unrelated identifiers")
    func shortNeedleCollisions() {
        // "tv" (Off Task) inside an ordinary reverse-DNS identifier.
        #expect(AppCategorizer.category(forBundleIdentifier: "com.tvtropes.reader", appName: "Reader") == "Off Task")
        // "meet" (Meetings) inside a word that has nothing to do with meetings.
        #expect(AppCategorizer.category(forBundleIdentifier: "com.meetup.organiser", appName: "Organiser") == "Meetings")
        // "notes" (Reading) inside a note-adjacent but unrelated app.
        #expect(AppCategorizer.category(forBundleIdentifier: "com.banknotes.scanner", appName: "Scanner") == "Reading")
    }

    @Test("the app name is ignored when the bundle identifier is present")
    func nameIsNotConsulted() {
        // "Xcode" as a name, but an identifier that matches nothing.
        #expect(AppCategorizer.category(forBundleIdentifier: "com.example.tool", appName: "Xcode") == "Xcode")
    }
}
