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
    /// Resolved at write time so historical records keep the category they were
    /// filed under even if the rules change later.
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
}
