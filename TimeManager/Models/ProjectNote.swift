import Foundation
import SwiftData

/// A living project document. Entries link to it; they never own its lifetime.
@Model
final class ProjectNote {
    var id: UUID = UUID()
    var tab: LogTab?
    var title: String = ""
    var richText: Data = Data()
    var plainText: String = ""
    var createdAt: Date = Date.now
    var editedAt: Date = Date.now
    var isPinned: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.notes)
    var entries: [LogEntry] = []

    init(tab: LogTab, title: String = "", at date: Date = .now) {
        self.tab = tab
        self.title = title
        createdAt = date
        editedAt = date
    }

    var displayTitle: String { title.isEmpty ? "Untitled note" : title }
}
