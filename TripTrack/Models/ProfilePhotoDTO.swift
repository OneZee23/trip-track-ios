import Foundation

struct ProfilePhotoDTO: Codable, Hashable, Identifiable {
    let id: UUID
    var thumbnailUrl: String? = nil
    var originalUrl: String? = nil
    var takenAt: String? = nil
    var sortOrder: Int? = nil
}

extension ProfilePhotoDTO {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            thumbnailUrl: try? c.decodeIfPresent(String.self, forKey: .thumbnailUrl),
            originalUrl: try? c.decodeIfPresent(String.self, forKey: .originalUrl),
            takenAt: try? c.decodeIfPresent(String.self, forKey: .takenAt),
            sortOrder: try? c.decodeIfPresent(Int.self, forKey: .sortOrder))
    }
}
