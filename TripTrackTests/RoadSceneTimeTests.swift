import UIKit
import XCTest
@testable import TripTrack

final class RoadSceneTimeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    func testEveryHour() throws {
        let expected: [RoadSceneTime] = [
            .night, .night, .night, .night, .night, .dawn, .dawn, .dawn,
            .day, .day, .day, .day, .day, .day, .day, .day, .day,
            .sunset, .sunset, .sunset, .night, .night, .night, .night,
        ]
        for (hour, slot) in expected.enumerated() {
            XCTAssertEqual(RoadSceneTime.slot(for: try date(hour: hour), calendar: calendar), slot, "Час \(hour)")
        }
    }

    func testBoundariesToTheSecond() throws {
        for (hour, before, after) in [(5, RoadSceneTime.night, RoadSceneTime.dawn),
                                      (8, .dawn, .day), (17, .day, .sunset), (20, .sunset, .night)] {
            let boundary = try date(hour: hour)
            XCTAssertEqual(RoadSceneTime.slot(for: boundary.addingTimeInterval(-1), calendar: calendar), before)
            XCTAssertEqual(RoadSceneTime.slot(for: boundary, calendar: calendar), after)
            XCTAssertEqual(RoadSceneTime.slot(for: boundary.addingTimeInterval(1), calendar: calendar), after)
        }
        let midnight = try date(hour: 0)
        XCTAssertEqual(RoadSceneTime.slot(for: midnight.addingTimeInterval(-1), calendar: calendar), .night)
        XCTAssertEqual(RoadSceneTime.slot(for: midnight, calendar: calendar), .night)
    }

    func testCalendarTimeZoneDeterminesTheSlot() throws {
        let instant = try date(hour: 4)
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 3 * 3600))
        XCTAssertEqual(RoadSceneTime.slot(for: instant, calendar: calendar), .night)
        XCTAssertEqual(RoadSceneTime.slot(for: instant, calendar: local), .dawn)
        local.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 3600))
        XCTAssertEqual(RoadSceneTime.slot(for: instant, calendar: local), .night)
    }

    func testDaylightSavingUsesLocalHours() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        for (month, day) in [(3, 29), (10, 25)] {
            let dawn = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: month, day: day, hour: 5)))
            XCTAssertEqual(RoadSceneTime.slot(for: dawn.addingTimeInterval(-1), calendar: local), .night)
            XCTAssertEqual(RoadSceneTime.slot(for: dawn, calendar: local), .dawn)
        }
    }

    func testAllFourScenesLoadAsPreservedVectors() throws {
        let root = UnitGuard.repoRoot().appendingPathComponent("TripTrack/Resources/Assets.xcassets/RoadScene")
        for time in RoadSceneTime.allCases {
            XCTAssertNotNil(UIImage(named: time.assetName), time.rawValue)
            let folder = root.appendingPathComponent(time.rawValue + ".imageset")
            let contents = try Data(contentsOf: folder.appendingPathComponent("Contents.json"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any])
            let properties = try XCTUnwrap(json["properties"] as? [String: Bool])
            XCTAssertEqual(properties["preserves-vector-representation"], true)
            let svg = try String(contentsOf: folder.appendingPathComponent(time.rawValue + ".svg"), encoding: .utf8)
            XCTAssertTrue(svg.contains("shape-rendering=\"crispEdges\""))
        }
    }

    private func date(hour: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour)))
    }
}
