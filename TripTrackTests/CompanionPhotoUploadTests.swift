import XCTest
import CoreData
@testable import TripTrack

/// Task 6 — a companion adding a photo to a trip they don't own.
///
/// Four things this suite pins:
///  1. The companion upload path writes NO `TripPhotoEntity` — proven by
///     counting rows in the real shared CoreData store (the only store any
///     accidental regression, e.g. a stray call into the owner's
///     `TripRepository`, could possibly land in) before and after a call,
///     both on success and on failure.
///  2. **Both the thumbnail AND the original parts are sent, thumbnail
///     first.** This is not optional: the backend's
///     `SocialService.getTripPhotos` filters `WHERE thumbnail_url IS NOT
///     NULL`, so a photo uploaded WITHOUT a thumbnail is invisible to
///     every reader forever — `/social/trip/photos` is the only way a
///     companion's own photo is ever read back. An earlier version of
///     this file sent only the `original` part to sidestep a "phantom
///     thumbnail" concern; that was backwards — it manufactured a
///     guaranteed-invisible row on every single upload instead. Rejected
///     by review; see `CompanionPhotoUploadService`'s doc comment.
///  3. The two PER-IMAGE failure modes are asymmetric and both are pinned:
///     thumbnail failing THROWS (nothing is visible either way, so the
///     original is never even attempted); the original failing AFTER a
///     successful thumbnail returns `.degraded`, NOT a throw — the photo
///     IS visible, just not at full quality, and the caller must not
///     report that as a failure.
///  4. **Batch reporting matches reality — the bug review caught.** An
///     earlier version of `CompanionPhotoUploadController.upload` stopped
///     at the first failed image (`break`) while still reloading the
///     strip because an EARLIER image had landed, and reported a flat
///     "couldn't upload" regardless — so a companion picking several
///     photos could see some appear while being told the upload failed,
///     with the rest silently never attempted at all. `upload` now
///     attempts every image regardless of earlier failures and reports one
///     aggregate `BatchOutcome`; pinned here with genuine multi-element
///     arrays (all succeed; the first fails and the rest still get
///     attempted and succeed; all fail) — none of which existed before
///     this fix, which is exactly why the bug went unseen.
///  5. The add-photo control is offered only for an accepted companion on
///     a foreign trip, never for a stranger, a still-pending/declined
///     invite, or the owner — proven against the pure
///     `CompanionPhotoUploadModel.canAddPhoto`.
@MainActor
final class CompanionPhotoUploadTests: XCTestCase {
    private var session: URLSession!
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(session: session, tokenStore: TokenStore.shared)
    }

    override func tearDown() {
        // Self-healing safety net: if a mutation-testing run (or a real
        // regression) ever DID leak an orphaned photo row into the shared
        // store, don't let it linger into the next test run.
        purgeOrphanedPhotoEntities()
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func testImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    private func okResponseHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"ok","payload":{"photoId":"\#(UUID().uuidString)","url":"https://example.com/x.jpg","uploadStatus":1}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    private func errorResponseHandler() -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            let body = Data(#"{"status":"error","code":"PHOTO_UPLOAD_FAILED","message":"nope"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    /// Thread-safe "answer call N with response N" dispatcher — `startLoading`
    /// can run off the main actor, so plain capture of a mutable `Int` isn't
    /// safe. Used to make the thumbnail call succeed and the original call
    /// fail (or vice versa) within a single `upload`.
    private final class SequencedHandler: @unchecked Sendable {
        private let lock = NSLock()
        private var index = 0
        private let responses: [(URLRequest) throws -> (HTTPURLResponse, Data)]
        init(_ responses: [(URLRequest) throws -> (HTTPURLResponse, Data)]) { self.responses = responses }
        func handle(_ req: URLRequest) throws -> (HTTPURLResponse, Data) {
            lock.lock()
            let i = min(index, responses.count - 1)
            index += 1
            lock.unlock()
            return try responses[i](req)
        }
    }

    /// Thread-safe capture of each request's multipart body, read LIVE as
    /// the mock handler runs. Reading it back afterwards from
    /// `MockURLProtocol.recordedRequests` does NOT work: `APIClient
    /// .performMultipart` sets `httpBody` (`Data`) on the outgoing request,
    /// but by the time a custom `URLProtocol` sees it, `URLSession` has
    /// already converted it to an `httpBodyStream` — and, empirically
    /// confirmed via a throwaway probe, that stream is single-read and
    /// already drained by the time the whole `async` call has returned, so
    /// every post-hoc read comes back empty. Reading it synchronously
    /// inside the response handler (which runs as part of `startLoading`,
    /// before that draining happens) is the only place it's still intact.
    private final class BodyRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var bodies: [Data] = []
        func record(_ data: Data) {
            lock.lock()
            bodies.append(data)
            lock.unlock()
        }
    }

    private static func readBody(_ req: URLRequest) -> Data {
        if let body = req.httpBody { return body }
        guard let stream = req.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: 4096)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    /// Wraps a response handler so every request's body is captured into
    /// `recorder` (in call order) before the response is returned.
    private func recordingHandler(
        _ recorder: BodyRecorder,
        respondingWith next: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in
            recorder.record(Self.readBody(req))
            return try next(req)
        }
    }

    /// Reads the `Content-Disposition: form-data; name="<name>"` text field
    /// out of a captured multipart body — used to prove which `type`
    /// (`thumbnail`/`original`) a given request actually carried, not just
    /// how many requests were made.
    ///
    /// `MultipartFormDataBuilder.append(field:value:)` writes every text
    /// field BEFORE `append(fileField:...)` writes the binary JPEG part
    /// (`APIClient.performMultipart`: `for f in fields { ... }` runs
    /// first, `builder.append(fileField: ...)` runs after) — so decoding
    /// only a leading prefix of the body is enough to reach every text
    /// field this test cares about, and dodges `String(data:encoding:
    /// .utf8)` failing outright on the binary tail (a single non-UTF8 byte
    /// anywhere in the FULL body fails the WHOLE decode). `String
    /// (decoding:as:)` never fails — invalid bytes become U+FFFD — so even
    /// if the prefix boundary lands mid-binary, the text fields earlier in
    /// the prefix are still readable.
    private func multipartFieldValue(_ name: String, in body: Data) -> String? {
        let text = String(decoding: body.prefix(2048), as: UTF8.self)
        guard let nameRange = text.range(of: "name=\"\(name)\"") else { return nil }
        guard let headerEnd = text.range(of: "\r\n\r\n", range: nameRange.upperBound..<text.endIndex) else { return nil }
        let rest = text[headerEnd.upperBound...]
        let valueEnd = rest.range(of: "\r\n")?.lowerBound ?? rest.endIndex
        return String(rest[rest.startIndex..<valueEnd])
    }

    /// A `TripPhotoEntity` with no `trip` relationship is anomalous in the
    /// real app — `TripRepository.addPhoto` always sets `.trip` before
    /// saving, so the ONLY way one could exist is exactly the bug this
    /// task guards against: a companion-path write with no local
    /// `TripEntity` to attach to. Scoping the count to orphans keeps this
    /// test immune to whatever other trips/photos happen to already be in
    /// the shared store from app usage or other tests.
    private func orphanedPhotoCount() -> Int {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "TripPhotoEntity")
        req.predicate = NSPredicate(format: "trip == nil")
        return (try? ctx.count(for: req)) ?? -1
    }

    private func purgeOrphanedPhotoEntities() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "TripPhotoEntity")
        req.predicate = NSPredicate(format: "trip == nil")
        guard let orphans = try? ctx.fetch(req), !orphans.isEmpty else { return }
        orphans.forEach(ctx.delete)
        try? ctx.save()
    }

    // MARK: - 1. No CoreData write

    func testSuccessfulUpload_WritesNoCoreDataRow() async throws {
        let before = orphanedPhotoCount()
        MockURLProtocol.requestHandler = okResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))

        try await service.upload(tripId: UUID(), image: Self.testImage())

        XCTAssertEqual(orphanedPhotoCount(), before)
    }

    func testFailedUpload_WritesNoCoreDataRow() async throws {
        let before = orphanedPhotoCount()
        MockURLProtocol.requestHandler = errorResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))

        do {
            try await service.upload(tripId: UUID(), image: Self.testImage())
            XCTFail("expected throw")
        } catch {
            // expected
        }

        XCTAssertEqual(orphanedPhotoCount(), before)
    }

    // MARK: - 2. Both parts sent, thumbnail first

    func testSuccessfulUpload_SendsThumbnailThenOriginal() async throws {
        let recorder = BodyRecorder()
        MockURLProtocol.requestHandler = recordingHandler(recorder, respondingWith: okResponseHandler())
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))

        let outcome = try await service.upload(tripId: UUID(), image: Self.testImage())

        XCTAssertEqual(outcome, .full)
        let requests = MockURLProtocol.recordedRequests
        let bodies = recorder.bodies
        // Guarded (not a second `XCTAssertEqual`) so a regression that
        // drops a part fails cleanly with a message instead of crashing
        // the whole process on the out-of-bounds index below.
        guard requests.count == 2, bodies.count == 2 else {
            XCTFail("must send BOTH parts — a photo with no thumbnail is invisible server-side; got \(requests.count) request(s)")
            return
        }
        XCTAssertEqual(requests[0].url?.path, APIEndpoint.photoUpload)
        XCTAssertEqual(requests[1].url?.path, APIEndpoint.photoUpload)
        XCTAssertEqual(multipartFieldValue("type", in: bodies[0]), "thumbnail", "thumbnail must go FIRST")
        XCTAssertEqual(multipartFieldValue("type", in: bodies[1]), "original")
        // Same photo row on the server — both parts must carry the same id.
        let photoId0 = multipartFieldValue("photoId", in: bodies[0])
        let photoId1 = multipartFieldValue("photoId", in: bodies[1])
        XCTAssertNotNil(photoId0)
        XCTAssertEqual(photoId0, photoId1)
    }

    func testThumbnailFailure_ThrowsAndNeverAttemptsOriginal() async {
        MockURLProtocol.requestHandler = errorResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))

        do {
            _ = try await service.upload(tripId: UUID(), image: Self.testImage())
            XCTFail("expected throw when the required thumbnail part fails")
        } catch {
            // expected
        }

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1, "original must never be attempted once the thumbnail failed")
    }

    func testOriginalFailure_ReturnsDegradedNotThrow() async throws {
        let seq = SequencedHandler([okResponseHandler(), errorResponseHandler()])
        MockURLProtocol.requestHandler = { try seq.handle($0) }
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))

        let outcome = try await service.upload(tripId: UUID(), image: Self.testImage())

        XCTAssertEqual(outcome, .degraded, "thumbnail landed — the photo IS visible, this is not a failure")
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
    }

    // MARK: - 3. Single-image outcome surfacing at the controller

    func testController_ThumbnailFailure_ReturnsFalseSetsAllFailed() async {
        MockURLProtocol.requestHandler = errorResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)

        let succeeded = await controller.upload(tripId: UUID(), images: [Self.testImage()])

        XCTAssertFalse(succeeded, "TripDetailView only reloads remotePhotos when this is true")
        XCTAssertEqual(controller.lastBatchOutcome, .allFailed)
        XCTAssertFalse(controller.isUploading)
    }

    func testController_OriginalFailure_ReturnsTrueSetsAllSucceededSomeDegraded() async {
        let seq = SequencedHandler([okResponseHandler(), errorResponseHandler()])
        MockURLProtocol.requestHandler = { try seq.handle($0) }
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)

        let succeeded = await controller.upload(tripId: UUID(), images: [Self.testImage()])

        XCTAssertTrue(succeeded, "the photo IS visible — TripDetailView must reload to show it")
        XCTAssertEqual(controller.lastBatchOutcome, .allSucceededSomeDegraded, "degraded is not a failure")
    }

    func testController_FullSuccess_ReturnsTrueSetsAllFull() async {
        MockURLProtocol.requestHandler = okResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)

        let succeeded = await controller.upload(tripId: UUID(), images: [Self.testImage()])

        XCTAssertTrue(succeeded)
        XCTAssertEqual(controller.lastBatchOutcome, .allFull)
    }

    func testController_EmptyPick_ReturnsFalseWithoutNetworkCall() async {
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)

        let succeeded = await controller.upload(tripId: UUID(), images: [])

        XCTAssertFalse(succeeded)
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 0)
    }

    // MARK: - 4. Multi-image BATCH reporting (the review's Finding 1)

    /// Three images, all fully succeed. Each needs thumbnail+original (2
    /// calls), so 6 requests total — proves every image in the batch was
    /// actually attempted, not just the first.
    func testController_BatchAllSucceed_ReturnsTrueSetsAllFull() async {
        MockURLProtocol.requestHandler = okResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)
        let images = [Self.testImage(), Self.testImage(), Self.testImage()]

        let succeeded = await controller.upload(tripId: UUID(), images: images)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(controller.lastBatchOutcome, .allFull)
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 6, "all 3 images × 2 parts each")
    }

    /// THE regression this finding is about: image 1's thumbnail fails
    /// (1 call), but images 2 and 3 must still be attempted and BOTH
    /// succeed fully (2 calls each) — 5 requests total. An old fail-fast
    /// `break` would have stopped after image 1's single failed call,
    /// recording only 1 request and never touching images 2/3 at all.
    func testController_BatchFirstFailsRestStillAttemptedAndSucceed_ReturnsPartial() async {
        let seq = SequencedHandler([
            errorResponseHandler(),  // image 1: thumbnail fails
            okResponseHandler(), okResponseHandler(),  // image 2: thumb + original
            okResponseHandler(), okResponseHandler(),  // image 3: thumb + original
        ])
        MockURLProtocol.requestHandler = { try seq.handle($0) }
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)
        let images = [Self.testImage(), Self.testImage(), Self.testImage()]

        let succeeded = await controller.upload(tripId: UUID(), images: images)

        XCTAssertTrue(succeeded, "2 of 3 landed — TripDetailView must reload to show them")
        XCTAssertEqual(controller.lastBatchOutcome, .partial(succeeded: 2, total: 3))
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 5, "images 2 and 3 must still be attempted after image 1 fails")
    }

    /// Every image's thumbnail fails. Both must still be independently
    /// attempted (2 requests, one per image), even though neither lands.
    func testController_BatchAllFail_ReturnsFalseSetsAllFailed() async {
        MockURLProtocol.requestHandler = errorResponseHandler()
        let service = CompanionPhotoUploadService(photos: R2PhotoStorage(client: client))
        let controller = CompanionPhotoUploadController(service: service)
        let images = [Self.testImage(), Self.testImage()]

        let succeeded = await controller.upload(tripId: UUID(), images: images)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(controller.lastBatchOutcome, .allFailed)
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2, "both images must be attempted independently")
    }

    // MARK: - 5. Add-photo control offered only for an accepted companion

    func testCanAddPhoto_AcceptedCompanionOnForeignTrip_True() {
        let me = UUID()
        let companions = [CompanionItem(accountId: me, displayName: "Me", avatarEmoji: nil, status: .accepted)]
        XCTAssertTrue(CompanionPhotoUploadModel.canAddPhoto(isOwn: false, companions: companions, viewerAccountId: me))
    }

    func testCanAddPhoto_Stranger_False() {
        let me = UUID()
        let companions = [CompanionItem(accountId: UUID(), displayName: "Someone else", avatarEmoji: nil, status: .accepted)]
        XCTAssertFalse(CompanionPhotoUploadModel.canAddPhoto(isOwn: false, companions: companions, viewerAccountId: me))
    }

    func testCanAddPhoto_PendingInvite_False() {
        let me = UUID()
        let companions = [CompanionItem(accountId: me, displayName: "Me", avatarEmoji: nil, status: .pending)]
        XCTAssertFalse(CompanionPhotoUploadModel.canAddPhoto(isOwn: false, companions: companions, viewerAccountId: me))
    }

    func testCanAddPhoto_DeclinedInvite_False() {
        let me = UUID()
        let companions = [CompanionItem(accountId: me, displayName: "Me", avatarEmoji: nil, status: .declined)]
        XCTAssertFalse(CompanionPhotoUploadModel.canAddPhoto(isOwn: false, companions: companions, viewerAccountId: me))
    }

    func testCanAddPhoto_OwnTrip_False() {
        let me = UUID()
        // Even if the roster somehow carried our own id as accepted, the
        // owner always gets the ordinary (CoreData) add-photo control.
        let companions = [CompanionItem(accountId: me, displayName: "Me", avatarEmoji: nil, status: .accepted)]
        XCTAssertFalse(CompanionPhotoUploadModel.canAddPhoto(isOwn: true, companions: companions, viewerAccountId: me))
    }

    func testCanAddPhoto_SignedOut_False() {
        let companions = [CompanionItem(accountId: UUID(), displayName: "Someone", avatarEmoji: nil, status: .accepted)]
        XCTAssertFalse(CompanionPhotoUploadModel.canAddPhoto(isOwn: false, companions: companions, viewerAccountId: nil))
    }

    func testCanAddPhoto_EmptyRoster_False() {
        XCTAssertFalse(CompanionPhotoUploadModel.canAddPhoto(isOwn: false, companions: [], viewerAccountId: UUID()))
    }

    // MARK: - 6. resolvedPhotosAfterReload — the post-upload reload guard
    //
    // `TripDetailView.uploadCompanionPhotos` captures `remotePhotos` BEFORE
    // firing a reload, then calls `loadRemotePhotos()`, which sets
    // `remotePhotos = []` on failure. Without this guard, ANY transient
    // failure of that follow-up reload — independent of the upload that
    // just succeeded — blanks the whole strip, including photos that were
    // already visible. The guard must fire on FAILURE only: a genuinely
    // empty but SUCCESSFUL reload (e.g. the last photo was deleted
    // server-side) must be trusted, not overridden back to the stale
    // `previous` list.

    private static func samplePhoto(_ label: String = "a") -> SocialTripPhoto {
        SocialTripPhoto(id: UUID(), caption: label, timestamp: Date(), thumbnailUrl: nil, originalUrl: nil)
    }

    func testResolvedPhotosAfterReload_FailedWithPreviousPhotos_KeepsPrevious() {
        let previous = [Self.samplePhoto("old1"), Self.samplePhoto("old2")]
        let reloaded: [SocialTripPhoto] = []

        let result = CompanionPhotoUploadModel.resolvedPhotosAfterReload(
            previous: previous, reloaded: reloaded, reloadFailed: true
        )

        XCTAssertEqual(result, previous, "a transient reload failure must not blank an already-populated strip")
    }

    func testResolvedPhotosAfterReload_FailedWithNoPreviousPhotos_StaysEmpty() {
        let previous: [SocialTripPhoto] = []
        let reloaded: [SocialTripPhoto] = []

        let result = CompanionPhotoUploadModel.resolvedPhotosAfterReload(
            previous: previous, reloaded: reloaded, reloadFailed: true
        )

        XCTAssertEqual(result, [], "the guard must not invent photos that were never there")
    }

    func testResolvedPhotosAfterReload_SucceededShorterThanPrevious_UsesReloaded() {
        // A photo genuinely deleted server-side must actually disappear —
        // the guard must not resurrect it just because `previous` was longer.
        let previous = [Self.samplePhoto("old1"), Self.samplePhoto("old2")]
        let reloaded = [Self.samplePhoto("old1")]

        let result = CompanionPhotoUploadModel.resolvedPhotosAfterReload(
            previous: previous, reloaded: reloaded, reloadFailed: false
        )

        XCTAssertEqual(result, reloaded, "a successful reload's list is the server's truth, even if shorter")
    }

    func testResolvedPhotosAfterReload_SucceededEmptyWithPreviousPhotos_UsesEmptyReloaded() {
        // THE subtle case: a successful-but-empty reload must win over a
        // non-empty `previous` — conflating "empty" with "failed" is
        // exactly how this kind of guard usually breaks.
        let previous = [Self.samplePhoto("old1"), Self.samplePhoto("old2")]
        let reloaded: [SocialTripPhoto] = []

        let result = CompanionPhotoUploadModel.resolvedPhotosAfterReload(
            previous: previous, reloaded: reloaded, reloadFailed: false
        )

        XCTAssertEqual(result, [], "an empty SUCCESSFUL reload is the server's truth, not a failure to guard against")
    }

    func testResolvedPhotosAfterReload_SucceededWithNoPreviousPhotos_UsesReloaded() {
        let previous: [SocialTripPhoto] = []
        let reloaded = [Self.samplePhoto("new1")]

        let result = CompanionPhotoUploadModel.resolvedPhotosAfterReload(
            previous: previous, reloaded: reloaded, reloadFailed: false
        )

        XCTAssertEqual(result, reloaded, "the first successful load of a trip's photos must appear")
    }
}
