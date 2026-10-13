import XCTest
@testable import TripTrack

@MainActor
final class ProductAnalyticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let date = Date(timeIntervalSince1970: 1_791_547_200)

    override func setUp() {
        super.setUp()
        suite = "ProductAnalyticsTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }
    private func service() -> ProductAnalytics {
        ProductAnalytics(defaults: defaults, now: { self.date }, networkEnabled: false)
    }
    private func state() throws -> ProductAnalytics.State {
        try JSONDecoder().decode(ProductAnalytics.State.self,
                                 from: XCTUnwrap(defaults.data(forKey: "productAnalytics.v1")))
    }

    func testOffByDefaultAndNoPreConsentHistory() throws {
        let analytics = service()
        let id = UUID()
        analytics.recordingStarted(id: id)
        analytics.recordingFinished(id: id, saved: true, eligible: true, elapsed: 0.2)
        analytics.atlasOpened()
        XCTAssertFalse(analytics.enabled)
        XCTAssertNil(defaults.data(forKey: "productAnalytics.v1"))
        analytics.setEnabled(true, hadTrips: true)
        XCTAssertEqual(try state().snapshot?.starts, 0)
        XCTAssertEqual(try state().snapshot?.hadTrips, true)
    }

    func testFirstAndRepeatSavesAndAtlasWithoutAnAccount() throws {
        let analytics = service()
        analytics.setEnabled(true)
        for duration in [0.01, 0.5, 2.0] {
            let id = UUID()
            analytics.recordingStarted(id: id)
            analytics.recordingFinished(id: id, saved: true, eligible: true, elapsed: duration)
        }
        analytics.atlasOpened()
        let snapshot = try XCTUnwrap(state().snapshot)
        XCTAssertEqual(snapshot.starts, 3)
        XCTAssertEqual(snapshot.saves, 3)
        XCTAssertEqual(snapshot.fastSaves, 1)
        XCTAssertEqual(snapshot.mediumSaves, 1)
        XCTAssertEqual(snapshot.slowSaves, 1)
        XCTAssertEqual(snapshot.firstSaveDay, ProductAnalytics.day(date))
        XCTAssertEqual(snapshot.secondSaveDay, snapshot.firstSaveDay)
        XCTAssertEqual(snapshot.atlasOpens, 1)
    }

    func testInterruptedRecordingSurvivesRelaunchAndDuplicateFinishDoesNotCount() throws {
        let id = UUID()
        let analytics = service()
        analytics.setEnabled(true)
        analytics.recordingStarted(id: id)
        let restored = service()
        restored.recordingStarted(id: id)
        restored.recordingFinished(id: id, saved: true, eligible: true, elapsed: 0.3)
        restored.recordingFinished(id: id, saved: true, eligible: true, elapsed: 0.3)
        XCTAssertEqual(try state().snapshot?.starts, 1)
        XCTAssertEqual(try state().snapshot?.saves, 1)
    }

    func testFailedAndJunkSavesNeverBecomeActivation() throws {
        let analytics = service()
        analytics.setEnabled(true)
        let failed = UUID()
        analytics.recordingStarted(id: failed)
        analytics.recordingFinished(id: failed, saved: false, eligible: true, elapsed: 1)
        let junk = UUID()
        analytics.recordingStarted(id: junk)
        analytics.recordingFinished(id: junk, saved: true, eligible: false, elapsed: 0.1)
        // A restored/imported trip without a matching recording start is ignored.
        analytics.recordingFinished(id: UUID(), saved: true, eligible: true, elapsed: 0.1)
        XCTAssertEqual(try state().snapshot?.starts, 2)
        XCTAssertEqual(try state().snapshot?.saveFailures, 1)
        XCTAssertEqual(try state().snapshot?.saves, 0)
        XCTAssertNil(try state().snapshot?.firstSaveDay)
    }

    func testRevocationErasesLocalCountersAndQueuesServerDeletionAcrossRelaunch() throws {
        let analytics = service()
        analytics.setEnabled(true)
        let token = try XCTUnwrap(state().snapshot?.token)
        analytics.atlasOpened()
        analytics.setEnabled(false)
        let restored = service()
        restored.atlasOpened()
        XCTAssertFalse(restored.enabled)
        XCTAssertTrue(restored.deletionPending)
        XCTAssertNil(try state().snapshot)
        XCTAssertEqual(try state().pendingErase, [token])
        restored.setEnabled(true)
        XCTAssertNotEqual(try state().snapshot?.token, token)
        XCTAssertEqual(try state().snapshot?.atlasOpens, 0)
    }

    func testPayloadHasOnlyApprovedFieldsAndNeverContainsLocalTripID() throws {
        let analytics = service()
        analytics.setEnabled(true)
        let id = UUID()
        analytics.recordingStarted(id: id)
        let data = try JSONEncoder().encode(XCTUnwrap(state().snapshot))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["schema", "token", "revision", "cohortDay", "observedDay",
            "hadTrips", "starts", "saves", "saveFailures", "atlasOpens", "fastSaves", "mediumSaves", "slowSaves"]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(id.uuidString))
    }

    func testNetworkFailureRetriesSameRevisionAndRevocationDeletesInsteadOfUploading() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageTestProtocol.handler = nil }
        let analytics = ProductAnalytics(defaults: defaults, now: { self.date },
                                         session: session, networkEnabled: true)
        analytics.setEnabled(true)
        let original = try XCTUnwrap(state().snapshot)
        let failed = expectation(description: "transient failure")
        UsageTestProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "x-access-token"))
            failed.fulfill()
            return 503
        }
        analytics.flush()
        await fulfillment(of: [failed], timeout: 2)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try state().acknowledgedRevision, 0)
        XCTAssertEqual(try state().snapshot, original)

        let retried = expectation(description: "retry")
        UsageTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "snapshot")
            retried.fulfill()
            return 204
        }
        analytics.flush()
        await fulfillment(of: [retried], timeout: 2)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try state().acknowledgedRevision, original.revision)
        analytics.setEnabled(false)
        let erased = expectation(description: "delete even while disabled")
        UsageTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "erase")
            erased.fulfill()
            return 204
        }
        analytics.flush()
        await fulfillment(of: [erased], timeout: 2)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(try state().pendingErase.isEmpty)
        XCTAssertFalse(analytics.enabled)
    }
}

private final class UsageTestProtocol: URLProtocol {
    static var handler: ((URLRequest) -> Int)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = Self.handler?(request) ?? 500
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
