import XCTest
import CoreLocation
@testable import TripTrack

/// P-I2: measures the exact regression `SocialFeedCardView` was paying —
/// `SocialFeedTrip.previewCoordinates` decoded its base64 polyline on
/// EVERY access with no cache, unlike `Trip.previewCoordinates` (which has
/// carried an `NSCache` since the feed-scroll fix). `mapSection` and the
/// diagnostics logger both read it in `body`, and `SocialFeedStore.trips`
/// republishes the whole array on every reaction/comment/photo bump — so a
/// visible card redecoded its route on events that touched a DIFFERENT
/// card. This file measures decode cost directly (no UI needed, no
/// backend needed) so the fix has a number, not a feeling.
final class FeedPreviewCachePerfTests: XCTestCase {

    /// ~220 points — a realistic simplified feed-card preview polyline
    /// (RDP-simplified route, same order of magnitude as a real trip's
    /// `previewPolyline`).
    private func samplePolylineBase64() -> String {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0..<220 {
            let t = Double(i) / 219
            coords.append(CLLocationCoordinate2D(
                latitude: 45.0 + t * 0.8 + sin(Double(i) * 0.3) * 0.001,
                longitude: 38.9 + t * 1.1 + cos(Double(i) * 0.3) * 0.001
            ))
        }
        return Trip.encodePolyline(coords).base64EncodedString()
    }

    private func makeTrip(polyline: String) -> SocialFeedTrip {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "author": ["id": UUID().uuidString, "displayName": "Test", "profileLevel": 1],
            "title": NSNull(), "description": NSNull(),
            "startDate": "2026-01-01T00:00:00Z", "endDate": NSNull(),
            "distance": 12345.0, "duration": 3600,
            "maxSpeed": NSNull(), "elevation": NSNull(), "maxAltitude": NSNull(),
            "drivingTime": NSNull(), "stoppedTime": NSNull(), "region": NSNull(),
            "isPrivate": false, "previewPolyline": polyline,
            "photoCount": 0, "firstPhotoThumbnail": NSNull(), "vehicle": NSNull(),
            "reactionCount": 0, "reactionBreakdown": [], "myReaction": NSNull(),
            "badgeIds": [], "commentCount": 0
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(SocialFeedTrip.self, from: data)
    }

    /// Direct decode cost — what EVERY `previewCoordinates` access paid
    /// before the cache existed (base64 decode + `Trip.decodePolyline`).
    private func timeUncachedDecode(_ polylineB64: String, rounds: Int) -> TimeInterval {
        let started = Date()
        for _ in 0..<rounds {
            guard let data = Data(base64Encoded: polylineB64) else { continue }
            _ = Trip.decodePolyline(data)
        }
        return Date().timeIntervalSince(started)
    }

    func testCachedAccessIsCheaperThanRepeatedDecode() {
        let polyline = samplePolylineBase64()
        let trip = makeTrip(polyline: polyline)
        let rounds = 500 // ~feed cards touched by one scroll + a few reaction bursts

        // BEFORE (simulated): what the old, cache-less property paid —
        // every single access is a fresh base64 + Float32 decode.
        let uncached = timeUncachedDecode(polyline, rounds: rounds)

        // AFTER (actual fix): first access misses and populates the
        // NSCache; every access after that is a dictionary-style lookup.
        _ = trip.previewCoordinates // warm the cache once
        let cachedStart = Date()
        for _ in 0..<rounds {
            _ = trip.previewCoordinates
        }
        let cached = Date().timeIntervalSince(cachedStart)

        let speedup = uncached / max(cached, 0.000_001)
        print(
            "PREVIEW-CACHE-PERF rounds=\(rounds) "
            + "uncached_total=\(String(format: "%.4f", uncached))s "
            + "cached_total=\(String(format: "%.4f", cached))s "
            + "speedup=\(String(format: "%.1f", speedup))x"
        )

        // Correctness: caching must not change the answer.
        XCTAssertEqual(trip.previewCoordinates.count, 220)

        // The cache is meant to turn an O(n) decode into an O(1) lookup —
        // assert a conservative floor so a future change that quietly
        // removes the cache fails loudly here instead of only showing up
        // as a slow scroll on-device.
        XCTAssertLessThan(cached, uncached / 3,
            "cached previewCoordinates access should be well under a third of decoding every time")
    }
}
