import Foundation
import SwiftData

/// Foundation owns observer delivery and removal, both thread-safe. The token
/// is immutable and its callback explicitly returns to the main actor.
final class TimerStoreObservation: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(onSave: @escaping @Sendable (Set<PersistentIdentifier>) -> Void) {
        token = NotificationCenter.default.addObserver(forName: ModelContext.didSave,
                                                       object: nil, queue: .main) { notification in
            var deleted: Set<PersistentIdentifier> = []
            for key in [ModelContext.NotificationKey.deletedIdentifiers, .invalidatedAllIdentifiers] {
                let value = notification.userInfo?[key] ?? notification.userInfo?[key.rawValue]
                if let ids = value as? [PersistentIdentifier] { deleted.formUnion(ids) }
                if let ids = value as? Set<PersistentIdentifier> { deleted.formUnion(ids) }
            }
            onSave(deleted)
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
