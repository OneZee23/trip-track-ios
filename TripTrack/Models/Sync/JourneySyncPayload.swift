import Foundation

struct JourneySyncPayload: Codable {
    let id: UUID
    let title: String?
    let startDate: Date
    let endDate: Date?
    let excludedTripIds: [UUID]
    let coverPhotoId: UUID?
    let isPrivate: Bool
    let conflictVersion: Int
    let lastModifiedAt: Date
    var serverCreatedAt: Date?

    init(journey j: Journey) {
        id = j.id; title = j.title; startDate = j.startDate; endDate = j.endDate
        excludedTripIds = j.excludedTripIds; coverPhotoId = j.coverPhotoId
        isPrivate = j.isPrivate; conflictVersion = j.conflictVersion
        lastModifiedAt = j.lastModifiedAt; serverCreatedAt = j.serverCreatedAt
    }
}
