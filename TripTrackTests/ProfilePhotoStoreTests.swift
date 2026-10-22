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

    func testOnlyAFreshSnapshotRemovesPhotosDeletedElsewhere() async throws {
        let id = UUID()
        store.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/t.jpg",
                                     originalUrl: "https://example.invalid/o.jpg")])
        let requested = store.uploadRevision
        try await store.add(jpeg())
        // Requested before the local add: it cannot know about it, so it may
        // add but never remove.
        store.restore([], revision: requested)
        XCTAssertTrue(store.photos.contains { $0.id == id })
        store.restore([], revision: store.uploadRevision)
        XCTAssertFalse(store.photos.contains { $0.id == id }, "A fresh snapshot without it means deleted elsewhere")
        XCTAssertEqual(store.photos.count, 1, "The local, not yet uploaded photo stays")
    }

    func testRestoreConfirmsLateVariantsAndDropsRemoteOnlyPhotos() {
        let id = UUID()
        store.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/t.jpg")],
                      revision: store.uploadRevision)
        XCTAssertEqual(store.photos.first?.originalUploaded, false)
        store.restore([ProfilePhotoDTO(id: id, thumbnailUrl: "https://example.invalid/t.jpg",
                                     originalUrl: "https://example.invalid/o.jpg")],
                      revision: store.uploadRevision)
        XCTAssertEqual(store.photos.first?.originalUploaded, true, "a variant the server reports is confirmed")
        let partial = UUID()
        store.restore([ProfilePhotoDTO(id: partial, thumbnailUrl: "https://example.invalid/p.jpg")],
                      revision: store.uploadRevision)
        store.restore([], revision: store.uploadRevision)
        XCTAssertTrue(store.photos.isEmpty, "photos that only ever came from the server leave with it")
    }

    func testASnapshotFromBeforeAReorderCannotUndoIt() async throws {
        let first = try await store.add(jpeg())
        let second = try await store.add(jpeg())
        let requested = store.uploadRevision
        store.makeFirst(second)
        store.acknowledgeOrderForTesting()
        store.restore([ProfilePhotoDTO(id: first, thumbnailUrl: "https://example.invalid/1.jpg"),
                       ProfilePhotoDTO(id: second, thumbnailUrl: "https://example.invalid/2.jpg")],
                      revision: requested)
        XCTAssertEqual(store.photos.map(\.id), [second, first])
    }

    func testASnapshotRequestedWhileTheOrderWasInFlightCannotUndoIt() async throws {
        let first = try await store.add(jpeg())
        let second = try await store.add(jpeg())
        store.makeFirst(second)
        let requested = store.uploadRevision   // /auth/me starts before the order lands
        store.acknowledgeOrderForTesting()
        store.restore([ProfilePhotoDTO(id: first, thumbnailUrl: "https://example.invalid/1.jpg"),
                       ProfilePhotoDTO(id: second, thumbnailUrl: "https://example.invalid/2.jpg")],
                      revision: requested)
        XCTAssertEqual(store.photos.map(\.id), [second, first])
    }

    func testImportFromAPreviousSessionIsRefused() async throws {
        let session = store.session
        store.wipe()
        do {
            try await store.add(jpeg(), session: session)
            XCTFail("An import started before sign-out must not land in the next account")
        } catch is CancellationError {
        }
        XCTAssertTrue(store.photos.isEmpty)
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
