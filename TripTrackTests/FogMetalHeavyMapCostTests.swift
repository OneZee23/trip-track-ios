import CoreLocation
import MapKit
import Metal
import XCTest
@testable import TripTrack

/// GPU cost of one fog frame on the heaviest real public map (13 Oct 2026).
///
/// The library has the real map's shape — 43 trips with its preview sizes and
/// distances over 50–60° N, 48–130° E (`DebugForeignTripFixture.realShape`) —
/// built by the same code as the public map (`AtlasPreviewLayer`), no
/// person's coordinates. Measured 13 Oct on a simulator: country 0.7–0.8 ms,
/// city 0.03 ms per frame — not where the phone's heat came from, which is
/// why this is a budget and not the fix.
@MainActor
final class FogMetalHeavyMapCostTests: XCTestCase {
    private func layer() -> RevealedLayer {
        let trips: [Trip] = DebugForeignTripFixture.realShape.enumerated().map { i, t in
            let a = Double(i)
            let from = CLLocationCoordinate2D(latitude: 50 + (a * 3.7).truncatingRemainder(dividingBy: 10),
                                              longitude: 48 + (a * 19).truncatingRemainder(dividingBy: 82))
            let to = CLLocationCoordinate2D(latitude: from.latitude + sin(a) * 2,
                                            longitude: from.longitude + t.km / 70)
            let coords = (0..<t.points).map { j -> CLLocationCoordinate2D in
                let p = Double(j) / Double(t.points - 1)
                return CLLocationCoordinate2D(
                    latitude: from.latitude + (to.latitude - from.latitude) * p + sin(p * 40 + a) * 0.04,
                    longitude: from.longitude + (to.longitude - from.longitude) * p + cos(p * 33 + a) * 0.04)
            }
            return Trip(id: UUID(), startDate: Date(timeIntervalSince1970: 1_790_000_000 - a * 86_400),
                        previewPolyline: Trip.encodePolyline(coords))
        }
        return AtlasPreviewLayer.build(trips: trips, atlas: nil)
    }

    /// GPU milliseconds for one frame, best of five.
    private func gpuMilliseconds(layer: RevealedLayer, rect: MKMapRect, size: CGSize) throws -> (ms: Double, segments: Int) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = FogFrameEncoder(device: device),
              let params = FogOffscreen.params(rect: rect, sizePoints: size, scale: 3,
                                               palette: FogVeilPainter.palette)
        else { throw XCTSkip("Metal is not available") }
        let mesh = FogMesh.build(layer: layer, device: device)
        let segments = (mesh.chunks[params.lod] ?? []).reduce(0) { $0 + $1.count }
        let width = Int(params.drawableSize.width), height = Int(params.drawableSize.height)
        guard let coverage = FogFrameEncoder.makeCoverageTexture(device: device, width: width, height: height)
        else { throw XCTSkip("No coverage texture") }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: FogFrameEncoder.targetFormat,
                                                         width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        guard let target = device.makeTexture(descriptor: d) else { throw XCTSkip("No target") }
        var best = Double.infinity
        for _ in 0..<5 {
            guard let buffer = queue.makeCommandBuffer() else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            encoder.encode(mesh: mesh, params: params, coverage: coverage, target: pass, into: buffer)
            buffer.commit()
            buffer.waitUntilCompleted()
            best = min(best, (buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
        }
        return (best, segments)
    }

    func testCountryZoomFogFrameStaysWithinBudget() throws {
        let layer = layer()
        let size = CGSize(width: 430, height: 932)
        var box = MKMapRect.null
        for line in layer.polylines(for: .far) { box = box.isNull ? line.boundingMapRect : box.union(line.boundingMapRect) }
        let aspect = Double(size.height / size.width)
        let width = box.width * 1.1
        let country = MKMapRect(x: box.midX - width / 2, y: box.midY - width * aspect / 2,
                                width: width, height: width * aspect)
        let far = try gpuMilliseconds(layer: layer, rect: country, size: size)
        print("PROBE fog gpu country=\(String(format: "%.2f", far.ms)) ms segments=\(far.segments)")
        // A sixtieth of a second is 16.7 ms; the fog must leave the map most of it.
        XCTAssertLessThan(far.ms, 4, "Country-zoom fog frame: \(far.ms) ms")
    }
}
