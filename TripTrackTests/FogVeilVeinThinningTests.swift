import CoreGraphics
import XCTest
@testable import TripTrack

/// The vector vein is thinned to the screen and stitched (13 Oct 2026): a
/// 25 000 km public map handed `CAShapeLayer` tens of thousands of segments,
/// most shorter than a point, and the phone ran hot redrawing them on every
/// pinch. Thinning must not change what the eye sees: ends stay, kept vertices
/// do not move, and separate roads stay separate.
final class FogVeilVeinThinningTests: XCTestCase {
    private func points(of path: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            if e.type == .moveToPoint || e.type == .addLineToPoint { out.append(e.points[0]) }
        }
        return out
    }

    private func moves(of path: CGPath) -> Int {
        var n = 0
        path.applyWithBlock { if $0.pointee.type == .moveToPoint { n += 1 } }
        return n
    }

    func testShippedStepIsBelowTheThinnestLine() {
        // Thinner than half the thinnest network line, or the eye would see
        // the corners cut.
        XCTAssertLessThanOrEqual(FogVeilVein.minStepPoints, 1)
        XCTAssertLessThan(FogVeilVein.minStepPoints, RouteVeinRenderer.width(for: .fine) / 2)
    }

    func testDenseLineKeepsItsEndsAndDropsSubPointSteps() {
        let source = CGMutablePath()
        source.move(to: .zero)
        for i in 1...1000 { source.addLine(to: CGPoint(x: Double(i) * 0.05, y: 0)) }
        let net = CGMutablePath()
        FogVeilVein.appendThinned(source, to: net, transform: .identity, minStep: 0.5)
        let kept = points(of: net)
        XCTAssertEqual(kept.first, .zero)
        XCTAssertEqual(kept.last, CGPoint(x: 50, y: 0), "The last vertex must stay")
        XCTAssertLessThanOrEqual(kept.count, 102, "Steps under half a point are dropped")
        for (a, b) in zip(kept, kept.dropFirst().dropLast()) {
            XCTAssertGreaterThanOrEqual(hypot(b.x - a.x, b.y - a.y), 0.5 - 1e-9)
        }
    }

    func testSparseLineIsUntouched() {
        let source = CGMutablePath()
        source.move(to: .zero)
        source.addLine(to: CGPoint(x: 10, y: 0))
        source.addLine(to: CGPoint(x: 10, y: 10))
        let net = CGMutablePath()
        FogVeilVein.appendThinned(source, to: net, transform: .identity, minStep: 0.5)
        XCTAssertEqual(points(of: net), [.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    func testTinyTripStaysVisibleAsADot() {
        let source = CGMutablePath()
        source.move(to: CGPoint(x: 5, y: 5))
        source.addLine(to: CGPoint(x: 5.1, y: 5))
        source.addLine(to: CGPoint(x: 5.2, y: 5))
        let net = CGMutablePath()
        FogVeilVein.appendThinned(source, to: net, transform: .identity, minStep: 0.5)
        let kept = points(of: net)
        XCTAssertEqual(kept.first, CGPoint(x: 5, y: 5))
        XCTAssertEqual(kept.last, CGPoint(x: 5.2, y: 5), "A short trip keeps its end")
    }

    func testTransformIsAppliedBeforeMeasuring() {
        let source = CGMutablePath()
        source.move(to: .zero)
        for i in 1...100 { source.addLine(to: CGPoint(x: Double(i) * 10, y: 0)) }
        let net = CGMutablePath()
        FogVeilVein.appendThinned(source, to: net, transform: CGAffineTransform(scaleX: 0.01, y: 0.01),
                                  minStep: 0.5)
        let kept = points(of: net)
        XCTAssertEqual(kept.last!.x, 10, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(kept.count, 22)
    }

    func testTouchingRunsAreStitchedIntoOneLine() {
        let source = CGMutablePath()
        for i in 0..<10 {
            source.move(to: CGPoint(x: Double(i) * 10, y: 0))
            source.addLine(to: CGPoint(x: Double(i + 1) * 10, y: 0))
        }
        let net = CGMutablePath()
        FogVeilVein.appendThinned(source, to: net, transform: .identity, minStep: 1)
        XCTAssertEqual(moves(of: net), 1, "Runs that touch must become one line")
        XCTAssertEqual(points(of: net).last, CGPoint(x: 100, y: 0))
    }

    func testStitchingWorksAcrossSeparateAppends() {
        // Paths arrive per bucket; the seam between two buckets is stitched too.
        let a = CGMutablePath(); a.move(to: .zero); a.addLine(to: CGPoint(x: 10, y: 0))
        let b = CGMutablePath(); b.move(to: CGPoint(x: 10, y: 0)); b.addLine(to: CGPoint(x: 20, y: 0))
        let net = CGMutablePath()
        FogVeilVein.appendThinned(a, to: net, transform: .identity, minStep: 1)
        FogVeilVein.appendThinned(b, to: net, transform: .identity, minStep: 1)
        XCTAssertEqual(moves(of: net), 1)
    }

    func testSeparateLinesStaySeparate() {
        let source = CGMutablePath()
        source.move(to: .zero)
        source.addLine(to: CGPoint(x: 0.1, y: 0))
        source.move(to: CGPoint(x: 100, y: 0))
        source.addLine(to: CGPoint(x: 110, y: 0))
        let net = CGMutablePath()
        FogVeilVein.appendThinned(source, to: net, transform: .identity, minStep: 0.5)
        XCTAssertEqual(moves(of: net), 2, "Two trips must not be joined into one line")
        XCTAssertEqual(points(of: net).last, CGPoint(x: 110, y: 0))
    }
}
