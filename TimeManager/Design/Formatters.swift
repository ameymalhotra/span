import Foundation

/// Shared duration/date formatting. Previously each view carried its own
/// private helper, which is why a 90-minute session rendered as "90:00".
enum Format {

    /// Clock-style elapsed time. Drops the hours component below an hour, so
    /// short sessions stay compact: `04:12`, `1:04:12`.
    static func clock(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// Human-readable span for summaries: `3h 42m`, `42m`, `< 1m`.
    static func compact(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 1 { return duration > 0 ? "< 1m" : "0m" }
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Timeline gutter labels: `9 AM`, `12 PM`.
    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return hourFormatter.string(from: date)
    }

    /// `9:41 AM`
    static func timeOfDay(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Title for the day being viewed: `Today`, `Yesterday`, or `Fri, Sep 5`.
    static func dayTitle(_ date: Date, relativeTo reference: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: reference) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: reference),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return dayFormatter.string(from: date)
    }

    /// Single-letter weekday for the week strip.
    static func weekdayInitial(_ date: Date) -> String {
        String(weekdayFormatter.string(from: date).prefix(1))
    }

    static func percent(_ fraction: Double) -> String {
        if fraction <= 0 { return "0%" }
        if fraction < 0.01 { return "< 1%" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}
