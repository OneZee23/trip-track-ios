import XCTest
import MapKit
@testable import TripTrack

/// Подпись слоя — то, чем `FogMetalVeil.setLayer` отличает «этот мир уже
/// собран» от «собирай заново».
///
/// Уровней детали три, и наборов буферов на GPU тоже три. Ключ по одному
/// `.fine` (так было до фикс-волны 0.8.0, вопреки спеке §4) означал бы, что
/// слой, у которого сменились только `.mid` и `.far`, до GPU не доедет
/// вовсе: на масштабе страны туман остался бы вчерашним, и заметить это
/// можно было бы только глазами и только отъехав.
final class FogMeshSignatureTests: XCTestCase {

    /// Тот же слой — та же подпись. Без этого каждый повтор `setLayer`
    /// пересобирал бы сотни тысяч отрезков заново.
    func testTheSameLayerKeepsItsSignature() {
        let world = layer(fine: [line(0)], mid: [line(1)], far: [line(2)])
        XCTAssertEqual(FogMesh.signature(of: world), FogMesh.signature(of: world))
    }

    /// Сменился ТОЛЬКО грубый уровень — подпись обязана стать другой.
    func testACoarseOnlyChangeChangesTheSignature() {
        let fine = line(0), mid = line(1)
        let before = layer(fine: [fine], mid: [mid], far: [line(2)])
        let after = layer(fine: [fine], mid: [mid], far: [line(3)])
        XCTAssertNotEqual(FogMesh.signature(of: before), FogMesh.signature(of: after),
                          "иначе страна показывала бы вчерашний туман")
    }

    /// Пустой `.fine` при непустом `.far` — законный слой, и подпись у него
    /// не пустая. По одному `.fine` два таких слоя были бы неразличимы, то
    /// есть второй не собрался бы никогда.
    func testAnEmptyFineLodStillCarriesASignature() {
        let sparse = layer(fine: [], mid: [], far: [line(4)])
        XCTAssertEqual(FogMesh.signature(of: sparse).count, 1)
        XCTAssertNotEqual(FogMesh.signature(of: sparse),
                          FogMesh.signature(of: layer(fine: [], mid: [], far: [line(5)])))
    }

    /// Подпись покрывает все три уровня — счётом это видно прямее всего.
    func testSignatureCoversEveryLod() {
        let world = layer(fine: [line(0), line(1)], mid: [line(2)], far: [line(3)])
        XCTAssertEqual(FogMesh.signature(of: world).count, 4)
    }

    // MARK: Кирпичи

    /// Отрезок в точках КАРТЫ: подпись смотрит на тождество объектов, и
    /// география ей безразлична — важно лишь, что каждый вызов даёт НОВЫЙ
    /// `MKPolyline`.
    private func line(_ seed: Int) -> MKPolyline {
        let points = [
            MKMapPoint(x: 1_000 + Double(seed), y: 1_000),
            MKMapPoint(x: 1_100 + Double(seed), y: 1_100),
        ]
        return MKPolyline(points: points, count: points.count)
    }

    private func layer(fine: [MKPolyline], mid: [MKPolyline], far: [MKPolyline]) -> RevealedLayer {
        RevealedLayer(fine: MKMultiPolyline(fine), mid: MKMultiPolyline(mid),
                      far: MKMultiPolyline(far), cellCount: fine.count + mid.count + far.count,
                      openedKm: 0, regionIds: [])
    }
}
