import Foundation

struct TripPhoto: Identifiable {
    let id: UUID
    let filename: String
    let caption: String?
    let timestamp: Date
}
