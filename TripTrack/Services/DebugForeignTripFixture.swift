#if DEBUG && targetEnvironment(simulator)
import Foundation
import CoreLocation

/// Offline regression fixture for Feed → someone else's trip. No local trip
/// row, credentials or production traffic; the real navigation and detail
/// loading paths remain in use. Unavailable on physical devices and Release.
enum DebugForeignTripFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-debug-foreign-trip")
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForeignTripURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static let preview: String = {
        let coordinates = (0..<3300).map { i in
            let progress = Double(i) / 3299
            return CLLocationCoordinate2D(
                latitude: 55.75 + progress * 1.2,
                longitude: 37.62 + progress * 2.1 + sin(progress * 32) * 0.025)
        }
        return Trip.encodePolyline(coordinates).base64EncodedString()
    }()

    private static func trip(refreshed: Bool) -> [String: Any] {
        [
            "id": "D37A1000-0000-4000-8000-000000000081",
            "author": [
                "id": "D37A2000-0000-4000-8000-000000000081",
                "displayName": "Test Traveller", "avatarEmoji": "🚙", "profileLevel": 21
            ],
            "title": refreshed ? "Foreign trip updated" : "Foreign trip preview",
            "description": "Offline navigation regression fixture.",
            "startDate": "2026-09-24T09:00:00Z",
            "endDate": "2026-09-24T13:00:00Z",
            "distance": 240000, "duration": 14400,
            "maxSpeed": 28, "drivingTime": 13500, "stoppedTime": 900,
            "isPrivate": false, "previewPolyline": preview,
            "photoCount": 0, "reactionCount": 0, "reactionBreakdown": [],
            "badgeIds": [], "commentCount": 0
        ]
    }

    static func response(path: String) throws -> Data {
        let payload: [String: Any]
        if path.hasSuffix(APIEndpoint.socialFeed) {
            payload = ["trips": [trip(refreshed: false)]]
        } else if path.hasSuffix(APIEndpoint.socialTrip) {
            payload = ["item": trip(refreshed: true), "track": []]
        } else if path.hasSuffix(APIEndpoint.socialTripPhotos) {
            payload = ["photos": []]
        } else if path.hasSuffix(APIEndpoint.socialReactions) {
            payload = ["reactions": []]
        } else if path.hasSuffix(APIEndpoint.socialComments) {
            payload = ["comments": []]
        } else if path.hasSuffix(APIEndpoint.companionsList) {
            payload = ["items": [], "isOwnerView": false]
        } else {
            // Catch every other API request too: this fixture never falls
            // through to a real server, including incidental startup writes.
            return try JSONSerialization.data(withJSONObject: [
                "status": "error", "code": "FIXTURE_UNSUPPORTED",
                "message": "Endpoint is outside the offline trip fixture"
            ])
        }
        return try JSONSerialization.data(withJSONObject: ["status": "ok", "payload": payload])
    }
}

private final class ForeignTripURLProtocol: URLProtocol {
    private var work: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let job = DispatchWorkItem { [weak self] in
            guard let self, let url = self.request.url else { return }
            do {
                let data = try DebugForeignTripFixture.response(path: url.path)
                let response = HTTPURLResponse(url: url, statusCode: 200,
                                               httpVersion: nil,
                                               headerFields: ["Content-Type": "application/json"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        work = job
        // A separate response after presentation must update the title; a
        // frozen SwiftUI graph can otherwise look like a successful render.
        let delay = request.url?.path.hasSuffix(APIEndpoint.socialTrip) == true ? 0.5 : 0.05
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: job)
    }

    override func stopLoading() { work?.cancel() }
}
#endif
