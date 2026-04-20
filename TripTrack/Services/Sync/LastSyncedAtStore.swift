import Foundation

enum LastSyncedAtStore {
    private static let prefix = "com.triptrack.sync.lastSyncedAt"

    static func get(accountId: UUID) -> Date? {
        UserDefaults.standard.object(forKey: "\(prefix).\(accountId)") as? Date
    }

    static func set(_ date: Date, for accountId: UUID) {
        UserDefaults.standard.set(date, forKey: "\(prefix).\(accountId)")
    }

    static func reset(for accountId: UUID) {
        UserDefaults.standard.removeObject(forKey: "\(prefix).\(accountId)")
    }
}
