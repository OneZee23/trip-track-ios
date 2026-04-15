import Foundation

/// Abstraction over remote photo storage (S3, R2, etc).
/// Concrete implementation will be provided when server is ready.
protocol RemotePhotoStorage {
    func upload(data: Data, path: String) async throws -> URL
    func download(from url: URL) async throws -> Data
    func delete(path: String) async throws
}
