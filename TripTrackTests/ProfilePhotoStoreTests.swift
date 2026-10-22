import XCTest
import UIKit
@testable import TripTrack

@MainActor
final class ProfilePhotoStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ProfilePhotoStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ProfilePhotoStore(directory: directory, syncEnabled: false)
    }
    override func tearDown() async throws {
        store.wipe()
        try? FileManager.default.removeItem(at: directory)
    }

    private func jpeg() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
    }

    func testAddAndNinePhotoLimit() async throws {
        let data = try jpeg()
        for _ in 0..<9 { try await store.add(data) }
        XCTAssertEqual(store.photos.count, 9)
        do { try await store.add(data); XCTFail("Tenth photo must be rejected") }
        catch ProfilePhotoStore.StoreError.limitReached { }
        XCTAssertEqual(store.photos.count, 9)
    }

    func testDeleteRemovesFileAndPersistsTombstone() async throws {
        let id = try await store.add(jpeg())
        let photo = try XCTUnwrap(store.photos.first)
        let file = try XCTUnwrap(store.fileURL(photo))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.delete(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let restored = ProfilePhotoStore(directory: directory, syncEnabled: false)
        restored.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/deleted.jpg")])
        XCTAssertTrue(restored.photos.isEmpty, "Offline deletion must survive a stale server snapshot")
    }

    func testReorderAndMetadataRoundTrip() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try await store.add(jpeg(), takenAt: date)
        let second = try await store.add(jpeg())
        store.makeFirst(second)
        let restored = ProfilePhotoStore(directory: directory, syncEnabled: false)
        XCTAssertEqual(restored.photos.map(\.id), [second, first])
        XCTAssertEqual(restored.photos.map(\.order), [0, 1])
        XCTAssertEqual(restored.photos.last?.takenAt, date)
        XCTAssertEqual(restored.photos, store.photos)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testRestoreSignedURLsWithoutLocalFiles() {
        let id = UUID()
        store.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/thumb.jpg?signature=1",
                                     originalUrl: "https://example.invalid/original.jpg?signature=1")])
        XCTAssertEqual(store.photos.first?.id, id)
        XCTAssertNil(store.photos.first?.filename)
        XCTAssertEqual(store.photos.first?.thumbnailURL, "https://example.invalid/thumb.jpg?signature=1")
        store.restore(nil)
        XCTAssertEqual(store.photos.count, 1)
        store.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/thumb.jpg?signature=2")])
        XCTAssertEqual(store.photos.count, 1)
        XCTAssertEqual(store.photos.first?.thumbnailURL, "https://example.invalid/thumb.jpg?signature=2")
    }

    func testRemoteVariantStateSurvivesMetadataRoundTrip() {
        let id = UUID()
        store.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/thumb.jpg",
                                     takenAt: "2026-10-22T09:00:00Z", sortOrder: 0)])
        let restored = ProfilePhotoStore(directory: directory, syncEnabled: false)
        XCTAssertEqual(restored.photos.first?.thumbnailUploaded, true)
        XCTAssertEqual(restored.photos.first?.originalUploaded, false)
        XCTAssertEqual(restored.photos.first?.takenAt, ISODate.parse("2026-10-22T09:00:00Z"))
        XCTAssertEqual(restored.photos, store.photos)
    }

    func testWipeRemovesFolderMetadataAndMemory() async throws {
        try await store.add(jpeg())
        store.wipe()
        XCTAssertTrue(store.photos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(ProfilePhotoStore(directory: directory, syncEnabled: false).photos.isEmpty)
    }

    func testInvalidImageDoesNotCreateMetadata() async {
        do { try await store.add(Data([1, 2, 3])); XCTFail("Invalid image") }
        catch { XCTAssertTrue(store.photos.isEmpty) }
    }
}
