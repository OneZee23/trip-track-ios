import XCTest
import CoreLocation
@testable import TripTrack

/// «Застолбить и отрезать»: первая поездка через ячейку владеет геометрией,
/// следующая по тому же асфальту не приносит ничего.
///
/// Половина тестов здесь — про ВТОРОЙ проезд. Шестьдесят копий одной улицы,
/// разъехавшихся шумом GPS, — это и есть та клякса, из-за которой 0.7.0 вообще
/// переписывает карту.
final class RevealBuilderTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)

    private func line(northMetres: Double, points: Int) -> [CLLocationCoordinate2D] {
        (0..<points).map { i in
            let t = Double(i) / Double(points - 1)
            return CLLocationCoordinate2D(
                latitude: start.latitude + (northMetres * t) / 111_320.0,
                longitude: start.longitude
            )
        }
    }

    private func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func allCells(_ patches: [String: TilePatch]) -> Int {
        patches.values.reduce(0) { $0 + $1.cells.count }
    }

    private func allRuns(_ patches: [String: TilePatch]) -> [[CLLocationCoordinate2D]] {
        patches.values.flatMap(\.runs)
    }

    // MARK: - Первый проезд

    func testStraightTripBecomesOneRunWithSeventyFiveMetreStep() {
        let coords = line(northMetres: 10_000, points: 3)
        let patches = RevealBuilder.patches(for: coords) { _ in [] }

        let runs = allRuns(patches)
        let points = runs.flatMap { $0 }
        XCTAssertGreaterThanOrEqual(allCells(patches), 125)

        // Прямая по одному меридиану пересекает несколько тайлов geohash-5,
        // поэтому прогонов столько же — но каждый непрерывен, и вместе они
        // покрывают все десять километров одной ниткой.
        for run in runs {
            for i in 1..<run.count {
                let step = metres(run[i - 1], run[i])
                XCTAssertGreaterThan(step, 30)
                XCTAssertLessThan(step, 130, "шаг прогона — примерно ячейка")
            }
        }
        let covered = runs.reduce(0.0) { sum, run in
            sum + zip(run, run.dropFirst()).reduce(0.0) { $0 + metres($1.0, $1.1) }
        }
        XCTAssertEqual(covered, 10_000, accuracy: 400)
        XCTAssertGreaterThan(points.count, 120)
    }

    func testTripLandsInItsOwnTiles() {
        let coords = line(northMetres: 12_000, points: 5)
        let patches = RevealBuilder.patches(for: coords) { _ in [] }
        XCTAssertGreaterThan(patches.count, 1, "двенадцать километров не влезают в один geohash-5")

        for (key, patch) in patches {
            // Ячейки тайла обязаны иметь в нём локальный индекс — иначе они
            // не переживут запись в базу.
            let encoded = RevealGrid.encode(Array(patch.cells), in: key)
            XCTAssertEqual(Set(RevealGrid.decode(encoded, in: key)), patch.cells,
                           "ячейка попала не в свой тайл")
            for run in patch.runs {
                for point in run.dropLast() {
                    XCTAssertEqual(RevealGrid.tileKey(for: point), key)
                }
            }
        }
    }

    // MARK: - Второй проезд

    func testSecondPassOverClaimedRoadGivesNothing() {
        let coords = line(northMetres: 10_000, points: 3)
        let first = RevealBuilder.patches(for: coords) { _ in [] }
        XCTAssertFalse(first.isEmpty)

        let second = RevealBuilder.patches(for: coords) { key in first[key]?.cells ?? [] }
        XCTAssertTrue(second.isEmpty, "по уже открытому не открывается ничего")
    }

    func testThereAndBackDrawsOneGeometry() {
        let out = line(northMetres: 5_000, points: 3)
        let round = out + out.reversed()
        let patches = RevealBuilder.patches(for: round) { _ in [] }

        let onlyOut = RevealBuilder.patches(for: out) { _ in [] }
        XCTAssertEqual(allCells(patches), allCells(onlyOut))

        let length = allRuns(patches).reduce(0.0) { sum, run in
            sum + zip(run, run.dropFirst()).reduce(0.0) { $0 + metres($1.0, $1.1) }
        }
        XCTAssertEqual(length, 5_000, accuracy: 400, "дорога туда и обратно — одна линия")
    }

    func testHalfOpenedRoadIsCutAtTheBorder() {
        let coords = line(northMetres: 10_000, points: 3)
        let half = line(northMetres: 5_000, points: 3)
        let opened = RevealBuilder.patches(for: half) { _ in [] }

        let patches = RevealBuilder.patches(for: coords) { key in opened[key]?.cells ?? [] }
        let runs = allRuns(patches)
        XCTAssertFalse(runs.isEmpty)

        let border = half[half.count - 1].latitude
        // Один шаг «внахлёст» разрешён нарочно: без него на стыке с уже
        // открытым осталась бы дыра шириной в ячейку.
        let overshoot = 2 * RevealGrid.cellDegrees
        for run in runs {
            for point in run {
                XCTAssertGreaterThan(point.latitude, border - overshoot,
                                     "прогон залез в уже открытое")
            }
        }
        let far = runs.flatMap { $0 }.map(\.latitude).max() ?? 0
        XCTAssertGreaterThan(far, coords.last!.latitude - 0.002, "вторая половина открыта")
    }

    // MARK: - Разрывы

    func testRecordingGapDoesNotDrawAcrossTheCountry() {
        let a = line(northMetres: 400, points: 3)
        let b = [
            CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
            CLLocationCoordinate2D(latitude: 55.754, longitude: 37.62),
        ]
        let patches = RevealBuilder.patches(for: a + b) { _ in [] }

        for run in allRuns(patches) {
            for i in 1..<run.count {
                XCTAssertLessThan(metres(run[i - 1], run[i]), RevealBuilder.runGapMetres,
                                  "прогон сшил разрыв записи")
            }
        }
    }

    func testTooShortLineGivesNoPatches() {
        XCTAssertTrue(RevealBuilder.patches(for: []) { _ in [] }.isEmpty)
        XCTAssertTrue(RevealBuilder.patches(for: [start]) { _ in [] }.isEmpty)
    }
}
