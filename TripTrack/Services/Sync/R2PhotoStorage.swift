import Foundation

enum PhotoType: String {
    case thumbnail
    case original
}

struct PhotoUploadResponse: Codable {
    let photoId: UUID
    let url: String
    let uploadStatus: Int16
}

struct PhotoURLRequest: Codable {
    let photoId: UUID
    let type: String
}

struct PhotoURLResponse: Codable {
    let url: String
    let expiresAt: String
}

@MainActor
final class R2PhotoStorage: RemotePhotoStorage {
    static let shared = R2PhotoStorage()
    private let client: APIClient

    init(client: APIClient = .shared) { self.client = client }

    // RemotePhotoStorage protocol conformance
    func upload(data: Data, path: String) async throws -> URL {
        throw APIError.transport("use uploadPhotoPart instead")
    }
    func download(from url: URL) async throws -> Data {
        try await client.getBytes(url: url)
    }
    func delete(path: String) async throws {
        // Server handles deletion through sync push
    }

    func uploadPhotoPart(
        tripId: UUID, photoId: UUID, type: PhotoType,
        data: Data, caption: String?, timestamp: Date
    ) async throws -> PhotoUploadResponse {
        var fields: [(name: String, value: String)] = [
            ("tripId", tripId.uuidString),
            ("photoId", photoId.uuidString),
            ("type", type.rawValue),
            ("timestamp", ISO8601DateFormatter().string(from: timestamp))
        ]
        if let caption = caption { fields.append(("caption", caption)) }
        return try await client.uploadMultipart(
            APIEndpoint.photoUpload,
            fields: fields,
            file: (name: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: data)
        )
    }

    func fetchPresignedURL(photoId: UUID, type: PhotoType) async throws -> URL {
        let res: PhotoURLResponse = try await client.post(
            APIEndpoint.photoURL,
            body: PhotoURLRequest(photoId: photoId, type: type.rawValue))
        guard let url = URL(string: res.url) else { throw APIError.decoding("bad url") }
        return url
    }
}
