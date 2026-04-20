import Foundation

struct SyncPullRequest: Codable {
    let lastSyncedAt: Date?
    let entityTypes: [String]?
}
