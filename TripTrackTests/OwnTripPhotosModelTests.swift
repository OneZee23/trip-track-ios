import XCTest
@testable import TripTrack

/// Coverage for `OwnTripPhotosModel.merge` — Fix 1 (companions review). The
/// trip owner's photo section used to read ONLY `trip.photos` (local
/// CoreData), so a companion's uploaded photo — which never gets a local
/// row on the owner's device by design (`/sync/pull` deliberately excludes
/// photos on trips the account doesn't own) — was permanently invisible to
/// the owner. Each test is built to fail if the rule it names is removed
/// from `merge`.
final class OwnTripPhotosModelTests: XCTestCase {

    private func localPhoto(_ id: UUID = UUID(), filename: String = "a.jpg", ts: Date = Date()) -> TripPhoto {
        TripPhoto(id: id, filename: filename, caption: nil, timestamp: ts)
    }

    private func remotePhoto(
        _ id: UUID = UUID(), ts: Date = Date(), thumb: String? = "thumb.url", original: String? = "orig.url"
    ) -> SocialTripPhoto {
        SocialTripPhoto(id: id, caption: nil, timestamp: ts, thumbnailUrl: thumb, originalUrl: original)
    }

    // MARK: - The core bug

    /// THE fix: a companion's photo — remote-only, no local counterpart —
    /// must appear in the owner's merged strip. Fails if `merge` drops
    /// remote items, or only ever returns local ones.
    func testCompanionsRemotePhoto_AppearsInMergedList() {
        let local = [localPhoto()]
        let companionPhotoId = UUID()
        let remote = [remotePhoto(companionPhotoId)]

        let result = OwnTripPhotosModel.merge(local: local, remote: remote)

        XCTAssertTrue(result.contains { $0.id == companionPhotoId },
                       "a companion's remote-only photo must be present in the owner's own photo section")
        XCTAssertEqual(result.count, 2, "both the local and the companion's photo must be present")
    }

    // MARK: - De-dup by id

    /// A photo that started local and finished syncing (same id on both
    /// sides — see `merge`'s doc comment on why the ids match) must appear
    /// EXACTLY ONCE, not twice. Fails if `merge` stops de-duping by id.
    func testPhotoPresentInBothLocalAndRemote_AppearsExactlyOnce() {
        let sharedId = UUID()
        let local = [localPhoto(sharedId, filename: "mine.jpg")]
        let remote = [remotePhoto(sharedId)]

        let result = OwnTripPhotosModel.merge(local: local, remote: remote)

        XCTAssertEqual(result.count, 1, "a photo present in both lists must appear exactly once")
        XCTAssertEqual(result.first?.id, sharedId)
    }

    /// The de-duped survivor must be the LOCAL entry (its filename,
    /// pointing at the file already on disk), not a second remote copy that
    /// would force a network fetch for a picture we already have locally.
    /// Fails if `merge` starts preferring the remote source for a shared id.
    func testPhotoPresentInBoth_KeepsLocalSourceNotRemote() {
        let sharedId = UUID()
        let local = [localPhoto(sharedId, filename: "mine.jpg")]
        let remote = [remotePhoto(sharedId)]

        let result = OwnTripPhotosModel.merge(local: local, remote: remote)

        guard case .local(let filename) = result.first?.source else {
            return XCTFail("expected the local entry to win for a shared id, got \(String(describing: result.first?.source))")
        }
        XCTAssertEqual(filename, "mine.jpg")
    }

    // MARK: - Pure local / pure remote

    func testOnlyLocalPhotos_AllPresent() {
        let local = [localPhoto(), localPhoto(), localPhoto()]
        let result = OwnTripPhotosModel.merge(local: local, remote: [])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy {
            if case .local = $0.source { return true }
            return false
        })
    }

    func testOnlyRemotePhotos_AllPresent() {
        let remote = [remotePhoto(), remotePhoto()]
        let result = OwnTripPhotosModel.merge(local: [], remote: remote)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy {
            if case .remote = $0.source { return true }
            return false
        })
    }

    func testEmptyBoth_ReturnsEmpty() {
        XCTAssertTrue(OwnTripPhotosModel.merge(local: [], remote: []).isEmpty)
    }

    // MARK: - Ordering

    /// Local rows come first — preserves the strip's existing order for
    /// anything already on screen today (adding the merge must not
    /// visually reshuffle a trip that has no companion photos at all).
    func testLocalPhotosOrderedBeforeRemoteOnlyPhotos() {
        let local = [localPhoto(), localPhoto()]
        let remote = [remotePhoto()]

        let result = OwnTripPhotosModel.merge(local: local, remote: remote)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Array(result.prefix(2)).map(\.id), local.map(\.id))
        XCTAssertEqual(result.last?.id, remote[0].id)
    }
}
