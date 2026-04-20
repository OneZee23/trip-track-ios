import Foundation
import ImageIO

enum PhotoType: String {
    case thumbnail
    case original
}

/// Re-encodes JPEG data with all metadata stripped (EXIF, GPS, IPTC, XMP).
/// Returns original data if re-encoding fails.
private func stripImageMetadata(_ jpegData: Data) -> Data {
    guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else { return jpegData }
    let uti = CGImageSourceGetType(source) ?? ("public.jpeg" as CFString)
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else { return jpegData }
    let options: [CFString: Any] = [
        kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
        kCGImageMetadataShouldExcludeGPS: kCFBooleanTrue as Any,
        kCGImageMetadataShouldExcludeXMP: kCFBooleanTrue as Any,
    ]
    var err: Unmanaged<CFError>?
    guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &err) else {
        return jpegData
    }
    return output as Data
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
        let cleanData = stripImageMetadata(data)
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
            file: (name: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: cleanData)
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
