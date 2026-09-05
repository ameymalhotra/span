import Foundation
import SwiftData

/// A stretch of time spent in one app — the passively tracked layer of the
/// timeline, written by `ActivityTracker`.
///
/// Records are coalesced before they are stored: flicking through three apps
/// with Cmd-Tab produces one record for wherever you land, not three. See
/// `ActivityTracker.minimumRecordedDuration`.
@Model
final class ActivityRecord {
    var id: UUID = UUID()
    /// Display name, e.g. "Xcode". Kept alongside the bundle id because an app
    /// can be uninstalled and we still want its history to read properly.
    var appName: String = ""
    var bundleIdentifier: String?
    /// Focused window title at the time, when Accessibility access is granted.
    var windowTitle: String?
    /// Browser address, when the frontmost app is a supported browser and
    /// automation access is granted.
    var url: String?
    var startedAt: Date = Date.now
    var endedAt: Date = Date.now
    /// True when this span represents the user being away from the keyboard,
    /// so breaks can be rendered as gaps rather than as work.
    var isIdle: Bool = false
    /// The category resolved when the record was written.
    ///
    /// A fallback rather than the answer: `currentCategory(for:)` re-resolves
    /// from the rules in force now, so re-filing an app corrects the time
    /// already recorded for it — which is the whole point of being able to
    /// re-file one. This is what a record with no bundle identifier falls back
    /// to, since there is nothing to re-resolve from.
    var categoryName: String?

    init(
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String? = nil,
        url: String? = nil,
        startedAt: Date,
        endedAt: Date,
        isIdle: Bool = false,
        categoryName: String? = nil
    ) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isIdle = isIdle
        self.categoryName = categoryName
    }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    /// The category this record counts towards now.
    ///
    /// Every surface that groups tracked time goes through here, so the
    /// timeline's rail, its legend and the day's breakdown cannot disagree
    /// about which category an app's time belongs to.
    static func currentCategory(for record: ActivityRecord) -> String {
        guard let bundleIdentifier = record.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return record.categoryName ?? record.appName
        }
        return AppCategorizer.category(forBundleIdentifier: bundleIdentifier,
                                       appName: record.appName)
    }
}
