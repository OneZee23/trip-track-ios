import CoreLocation
import Foundation
import XCTest
@testable import TripTrack

final class HiddenPartsVectorTests: XCTestCase {
    func testSharedVectors() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "hidden-parts-vectors", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let pointValues = try XCTUnwrap(root["points"] as? [[String: Any]])
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        let points = try pointValues.map { value -> TrackPoint in
            let time = try XCTUnwrap(value["t"] as? Double)
            let coordinate = try XCTUnwrap(value["c"] as? [Double])
            return TrackPoint(latitude: coordinate[0], longitude: coordinate[1], timestamp: origin.addingTimeInterval(time))
        }
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let input = try XCTUnwrap(item["input"] as? [String: Any])
            let expected = try XCTUnwrap(item["expect"] as? [String: Any])
            let sections = try XCTUnwrap(input["sections"] as? [[Double]]).map {
                HiddenSection(id: UUID(), from: origin.addingTimeInterval($0[0]), to: origin.addingTimeInterval($0[1]))
            }
            let zoneValue = input["zone"] as? [String: Any]
            let zone: Zone? = try zoneValue.map { value in
                let coordinate = try XCTUnwrap(value["c"] as? [Double])
                let radius = try XCTUnwrap(value["r"] as? Double)
                return (CLLocationCoordinate2D(latitude: coordinate[0], longitude: coordinate[1]), radius)
            }
            let breakTimes = try XCTUnwrap(input["recordingBreaks"] as? [Double]).map { origin.addingTimeInterval($0) }
            let result = HiddenPartsResolver.resolve(
                points: points, recordingBreaks: breakTimes,
                startMetres: try XCTUnwrap(input["startMetres"] as? Int),
                endMetres: try XCTUnwrap(input["endMetres"] as? Int), sections: sections, zone: zone
            )
            let ranges = result.hiddenRanges.map { [Int(($0.from.timeIntervalSince(origin) / 10).rounded()) * 10, Int(($0.to.timeIntervalSince(origin) / 10).rounded()) * 10] }
            XCTAssertEqual(ranges, expected["hiddenRanges"] as? [[Int]], name)
            let visibleRuns = result.visibleRuns.map { run -> [Int] in
                let start = points.firstIndex(where: { $0.id == run.first?.id }) ?? 0
                let end = points.firstIndex(where: { $0.id == run.last?.id }) ?? start
                return [start, end]
            }
            XCTAssertEqual(visibleRuns, expected["visibleRuns"] as? [[Int]], name)
            XCTAssertEqual(result.previewBreaks, expected["previewBreaks"] as? [Int], name)
            XCTAssertEqual(result.previewPoints.count, expected["previewPointCount"] as? Int, name)
            let expectedNumbers = try XCTUnwrap(expected["publicNumbers"] as? [String: Any], name)
            let distance = result.visibleRuns.reduce(0.0) { total, run in
                guard let first = run.first, let last = run.last,
                      let firstIndex = points.firstIndex(where: { $0.id == first.id }),
                      let lastIndex = points.firstIndex(where: { $0.id == last.id }) else { return total }
                return total + (lastIndex >= firstIndex
                    ? runDistance(points: points, from: firstIndex, through: lastIndex)
                    : 0)
            }
            XCTAssertEqual(distance, try XCTUnwrap(expectedNumbers["distance"] as? Double, name), accuracy: 0.5, name)
            let firstVisible = result.visibleRuns.first?.first?.timestamp.timeIntervalSince(origin)
            let lastVisible = result.visibleRuns.last?.last?.timestamp.timeIntervalSince(origin)
            XCTAssertEqual(firstVisible.map { Int($0.rounded()) }, expectedNumbers["start"] as? Int, name)
            XCTAssertEqual(lastVisible.map { Int($0.rounded()) }, expectedNumbers["end"] as? Int, name)
            let photoValues = try XCTUnwrap(root["photos"] as? [[String: Any]])
            let hiddenPhotos = try photoValues.compactMap { photo -> String? in
                let time = photo["capturedAt"] as? Double
                let coordinate = photo["coordinate"] as? [Double]
                let location = coordinate.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                guard HiddenPartsResolver.photoIsHidden(
                    capturedAt: time.map { origin.addingTimeInterval($0) }, coordinate: location,
                    resolution: result, points: points, zone: zone) else { return nil }
                return photo["id"] as? String
            }
            XCTAssertEqual(hiddenPhotos, expected["hiddenPhotoIds"] as? [String], name)
        }
    }

    private func runDistance(points: [TrackPoint], from first: Int, through last: Int) -> Double {
        guard last > first else { return 0 }
        return (first..<last).reduce(0) { total, index in
            total + GeometryUtils.haversineDistance(points[index].coordinate, points[index + 1].coordinate)
        }
    }

    /// Drawing reaches the visible neighbours and never crosses a pause (same table as Android).
    func testDrawnHiddenRunsReachTheVisibleNeighbours() {
        XCTAssertEqual(HiddenPartsResolver.drawnHiddenRuns(hidden: [true, false, false, false], segments: [0, 0, 0, 0]), [[0, 1]])
        XCTAssertEqual(HiddenPartsResolver.drawnHiddenRuns(hidden: [false, false, true, true, false], segments: [0, 0, 0, 0, 0]), [[1, 2, 3, 4]])
        XCTAssertEqual(HiddenPartsResolver.drawnHiddenRuns(hidden: [false, true, true, true, false], segments: [0, 0, 0, 1, 1]), [[0, 1, 2], [3, 4]])
        XCTAssertEqual(HiddenPartsResolver.drawnHiddenRuns(hidden: [false, false], segments: [0, 0]), [])
    }
}
