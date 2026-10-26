import XCTest
import Metal
@testable import TripTrack

/// Sentry APPLE-IOS-11: шейдеры тумана компилировались на главном потоке при
/// открытии «Атласа». Теперь их собирает фон на запуске, а экран и постер
/// берут готовое — один кодировщик на устройство.
final class FogPipelineCacheTests: XCTestCase {
    override func tearDown() {
        FogPipelineCache.resetForTesting()
        super.tearDown()
    }

    func testPrewarmBuildsOffMainAndEveryoneSharesIt() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal") }
        FogPipelineCache.resetForTesting()
        FogPipelineCache.prewarm()
        let deadline = Date().addingTimeInterval(10)
        var first: FogFrameEncoder?
        while Date() < deadline {
            first = FogPipelineCache.encoder(device: device)
            if first != nil { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let a = try XCTUnwrap(first)
        let b = try XCTUnwrap(FogPipelineCache.encoder(device: device))
        XCTAssertTrue(a === b, "Screen and poster must reuse one compiled encoder")
    }
}
