import XCTest
import CoreLocation
@testable import TripTrack

final class RawFixLogTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    func testLineIsLocaleProofAndCarriesTheDecision() {
        let fix = TrackTestKit.fix(east: 0, north: 0, speed: 12.5, after: 0, accuracy: 72.25)
        let line = RawFixLog.line(for: fix, decision: .reject(.accuracy))
        XCTAssertTrue(line.contains("72.25"))
        XCTAssertTrue(line.hasSuffix("reject:accuracy"))
        XCTAssertFalse(line.contains(";"))
    }

    func testRecordsOnlyWhileATripIsOpenAndMarksLifecycle() async throws {
        let log = RawFixLog(directory: dir)
        await log.record(line: "before")
        let id = UUID()
        await log.begin(tripId: id)
        await log.record(line: "during")
        await log.mark("background")
        await log.end()
        await log.record(line: "after")
        let text = try String(contentsOf: dir.appendingPathComponent("\(id.uuidString).csv"), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix(RawFixLog.header))
        XCTAssertTrue(text.contains("during"))
        XCTAssertTrue(text.contains("background"))
        XCTAssertFalse(text.contains("before"))
        XCTAssertFalse(text.contains("after"))
    }

    /// Координаты поездок в резервную копию не уезжают — как снимки.
    func testDirectoryIsExcludedFromBackup() async throws {
        let log = RawFixLog(directory: dir)
        await log.begin(tripId: UUID())
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testPurgeDropsFilesOlderThanRetention() async {
        let log = RawFixLog(directory: dir)
        await log.begin(tripId: UUID())
        await log.end()
        await log.purgeOld(now: Date().addingTimeInterval(Double(RawFixLog.retentionDays + 1) * 86_400))
        let left = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(left.isEmpty)
    }
}
