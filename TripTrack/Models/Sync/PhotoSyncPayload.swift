import Foundation

struct PhotoSyncPayload: Codable {
    let id: UUID
    let tripId: UUID
    let filename: String
    let caption: String?
    let timestamp: Date
    let remoteUrl: String?
    let thumbnailUrl: String?
    let sortOrder: Int
    let uploadStatus: Int16
    let lastModifiedAt: Date
}
