import XCTest
import CoreLocation
@testable import TripTrack

final class TripPhotoPreparationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func points() -> [TrackPoint] {
        (0...100).map { i in
            TrackPoint(latitude: 45 + Double(i) * 10 / 111_320, longitude: 38.9,
                       speed: 10, timestamp: start.addingTimeInterval(Double(i)))
        }
    }

    private func photo(at second: Double?, coordinate: CLLocationCoordinate2D? = nil) -> TripPhoto {
        TripPhoto(id: UUID(), filename: "test.jpg", caption: nil, timestamp: start,
                  capturedAt: second.map { start.addingTimeInterval($0) },
                  exifLatitude: coordinate?.latitude, exifLongitude: coordinate?.longitude)
    }

    private func assertSame(_ a: TripRouteLocator.Fix?, _ b: TripRouteLocator.Fix?,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a?.index, b?.index, file: file, line: line)
        XCTAssertEqual(a?.coordinate.latitude, b?.coordinate.latitude, file: file, line: line)
        XCTAssertEqual(a?.coordinate.longitude, b?.coordinate.longitude, file: file, line: line)
        XCTAssertEqual(a?.timestamp, b?.timestamp, file: file, line: line)
        XCTAssertEqual(a?.distanceFromStart, b?.distanceFromStart, file: file, line: line)
        XCTAssertEqual(a?.elapsedFromStart, b?.elapsedFromStart, file: file, line: line)
    }

    func testPreparedReadingsPreserveExifPriorityAndTimestampFallback() throws {
        let track = points()
        let ownCoordinate = photo(at: 90, coordinate: track[20].coordinate)
        let farExif = photo(at: 60, coordinate: CLLocationCoordinate2D(latitude: 50, longitude: 40))
        let timestampOnly = photo(at: 40)
        let noMetadata = photo(at: nil)
        let outsideTrip = photo(at: -10)
        let photos = [ownCoordinate, farExif, timestampOnly, noMetadata, outsideTrip]
        let prepared = try TripPhotoPlacement.prepare(
            photos: photos, checkpoints: [], points: track, startDate: start.addingTimeInterval(-30))

        XCTAssertEqual(prepared.placed.map(\.id), [ownCoordinate.id, farExif.id, timestampOnly.id])
        XCTAssertEqual(prepared.fixes[ownCoordinate.id]?.index, 20, "EXIF's pass wins over capture time")
        XCTAssertEqual(prepared.fixes[farExif.id]?.index, 60, "Reading falls back to capture time")
        XCTAssertEqual(prepared.placed.first { $0.id == farExif.id }?.latitude, 50,
                       "The pin still uses EXIF even when its reading comes from capture time")
        XCTAssertEqual(prepared.fixes[timestampOnly.id]?.elapsedFromStart, 70)
        XCTAssertNil(prepared.fixes[noMetadata.id])
        XCTAssertNil(prepared.fixes[outsideTrip.id])
        for photo in photos {
            let oldFix: TripRouteLocator.Fix?
            if let coordinate = photo.exifCoordinate,
               let pass = TripRouteLocator.passes(near: coordinate, in: track, radius: 300,
                                                  startDate: start.addingTimeInterval(-30)).first {
                oldFix = pass
            } else {
                oldFix = photo.capturedAt.flatMap {
                    TripRouteLocator.fix(at: $0, in: track, startDate: start.addingTimeInterval(-30))
                }
            }
            assertSame(prepared.fixes[photo.id], oldFix)
        }
    }

    func testNoLoosePhotosDoesNotCreateReadingsAndKeepsCheckpointLinks() throws {
        let track = points()
        let attached = photo(at: 50)
        let checkpoint = TripCheckpoint(timestamp: start.addingTimeInterval(50), latitude: 45,
                                        longitude: 38.9, distanceFromStart: 500, elapsedFromStart: 50,
                                        photoId: attached.id)
        let empty = try TripPhotoPlacement.prepare(photos: [], checkpoints: [checkpoint], points: track, startDate: start)
        XCTAssertTrue(empty.placed.isEmpty)
        XCTAssertTrue(empty.fixes.isEmpty)
        let linked = try TripPhotoPlacement.prepare(photos: [attached], checkpoints: [checkpoint], points: track, startDate: start)
        XCTAssertEqual(linked.links[checkpoint.id]?.map(\.id), [attached.id])
        XCTAssertTrue(linked.placed.isEmpty)
        XCTAssertTrue(linked.fixes.isEmpty)
    }

    func testReusableIndexKeepsBothPassesAndDistanceGateRules() {
        let outward = points()
        let back = outward.reversed().enumerated().map { i, p in
            TrackPoint(latitude: p.latitude, longitude: p.longitude,
                       horizontalAccuracy: i % 7 == 0 ? 200 : 5,
                       timestamp: start.addingTimeInterval(1_300 + Double(i)),
                       isInterpolated: i % 5 == 0)
        }
        let track = outward + back
        let index = TripRouteLocator.Index(points: track, startDate: start)
        let original = TripRouteLocator.passes(near: outward[50].coordinate, in: track, radius: 120, startDate: start)
        let prepared = index.passes(near: outward[50].coordinate)
        XCTAssertEqual(prepared.count, 2)
        XCTAssertEqual(prepared.count, original.count)
        for (a, b) in zip(prepared, original) { assertSame(a, b) }
        assertSame(index.fix(at: track.last!.timestamp),
                   TripRouteLocator.fix(at: track.last!.timestamp, in: track, startDate: start))
    }

    func testCancelledPreparationNeverReturnsPublishableOutput() async {
        let track = points()
        let photos = [photo(at: 50)]
        let start = start
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TripPhotoPlacement.prepareAsync(
                photos: photos, checkpoints: [], points: track, startDate: start)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled rebuild must not publish pins from its snapshot")
        } catch is CancellationError {
            // Expected, including cancellation before the worker starts.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReplacementWithSamePhotoCountGetsFreshReadings() async throws {
        let track = points()
        let old = photo(at: 20)
        let new = photo(at: 80)
        let first = try await TripPhotoPlacement.prepareAsync(photos: [old], checkpoints: [], points: track, startDate: start)
        let second = try await TripPhotoPlacement.prepareAsync(photos: [new], checkpoints: [], points: track, startDate: start)
        XCTAssertEqual(first.fixes[old.id]?.index, 20)
        XCTAssertNil(second.fixes[old.id])
        XCTAssertEqual(second.fixes[new.id]?.index, 80)
    }
}
