import XCTest
import CoreLocation
@testable import TripTrack

/// Загадка решается проездом, и радиус у неё свой на каждый тип: перевал
/// проезжают по дороге, маяк видно с берега.
final class RiddleMatcherTests: XCTestCase {

    private let point = CLLocationCoordinate2D(latitude: 43.6234, longitude: 41.4571)

    private func riddle(_ type: RiddleType, at coordinate: CLLocationCoordinate2D? = nil) -> Riddle {
        let place = coordinate ?? point
        return Riddle(
            id: "\(type.rawValue):\(GeohashEncoder.encode(latitude: place.latitude, longitude: place.longitude, precision: 7))",
            type: type, coordinate: place, name: "Gumbashi Pass", regionId: "RU-KC")
    }

    /// Прямая, проходящая в `metres` от загадки.
    private func trackPassing(_ metres: Double) -> [TrackPoint] {
        let line = DiscoveryTrackFixtures.offset(point, northMetres: metres)
        return DiscoveryTrackFixtures.line(
            from: DiscoveryTrackFixtures.offset(line, eastMetres: -500),
            to: DiscoveryTrackFixtures.offset(line, eastMetres: 500))
    }

    func testPassIsSolvedAtTwoHundredFiftyMetres() {
        let solved = RiddleMatcher.solved(track: trackPassing(250), candidates: [riddle(.pass)])

        XCTAssertEqual(solved.count, 1)
        XCTAssertEqual(solved.first?.riddle.type, .pass)
    }

    func testPassIsNotSolvedAtThreeHundredFifty() {
        XCTAssertTrue(RiddleMatcher.solved(track: trackPassing(350), candidates: [riddle(.pass)]).isEmpty)
    }

    /// Тот же трек, другой тип — другой ответ. Иначе `reach` был бы одной
    /// константой, и маяк пришлось бы «увидеть» с трёхсот метров.
    func testReachComesFromTheType() {
        let track = trackPassing(500)

        XCTAssertTrue(RiddleMatcher.solved(track: track, candidates: [riddle(.pass)]).isEmpty)
        XCTAssertEqual(RiddleMatcher.solved(track: track, candidates: [riddle(.lighthouse)]).count, 1)
        XCTAssertEqual(RiddleMatcher.solved(track: track, candidates: [riddle(.tripoint)]).count, 1)
    }

    /// «Туда и обратно» — две записи проезда у `TripRouteLocator`, но одна
    /// решённая загадка.
    func testThereAndBackSolvesOnce() {
        let out = trackPassing(100)
        let backStart = out.last!.timestamp.addingTimeInterval(3600)
        let back = DiscoveryTrackFixtures.line(
            from: out.last!.coordinate, to: out.first!.coordinate, startingAt: backStart)

        let solved = RiddleMatcher.solved(track: out + back, candidates: [riddle(.pass)])

        XCTAssertEqual(solved.count, 1)
    }

    func testEmptyInputsAreSilent() {
        XCTAssertTrue(RiddleMatcher.solved(track: trackPassing(10), candidates: []).isEmpty)
        XCTAssertTrue(RiddleMatcher.solved(track: [], candidates: [riddle(.pass)]).isEmpty)
        let single = [TrackPoint(latitude: point.latitude, longitude: point.longitude)]
        XCTAssertTrue(RiddleMatcher.solved(track: single, candidates: [riddle(.pass)]).isEmpty)
    }

    /// Каждая загадка отвечает за себя: дальняя не тянет за собой ближнюю.
    func testOnlyRiddlesOnTheTrackAreSolved() {
        let far = DiscoveryTrackFixtures.offset(point, northMetres: 5_000)
        let solved = RiddleMatcher.solved(
            track: trackPassing(50),
            candidates: [riddle(.pass), riddle(.pass, at: far)])

        XCTAssertEqual(solved.count, 1)
        XCTAssertEqual(solved.first?.riddle.coordinate.latitude ?? 0, point.latitude, accuracy: 1e-9)
    }
}
