import XCTest
import MapKit
@testable import TripTrack

/// Покой метал-тумана: `CADisplayLink` живёт только на жесте и хвост после
/// него.
///
/// Проверяется здесь то, что глазами не видно вовсе: на стоящей карте кадр
/// выглядит так же, тикает вуаль или нет, — а разница между «тиков нет» и
/// «сто двадцать тиков в секунду» это батарея всё время, пока открыт
/// «Атлас». Тот же вопрос и тем же способом задан прорези у машины в
/// `VeilSeatTests.testLiveRevealNeverOrdersARaster`.
///
/// Окна у вуали здесь нет, поэтому `currentDrawable` может не найтись —
/// `frames` считает кадры ПО ВЫЗОВУ `draw(_:)`, и это ровно то число, которое
/// тесту нужно: «сколько раз мы взялись рисовать».
@MainActor
final class FogMetalVeilTrackingTests: XCTestCase {

    func testAttachAloneStartsNoDisplayLink() throws {
        guard let veil = FogMetalVeil.make() else { throw XCTSkip("Metal недоступен") }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        XCTAssertFalse(veil.isTracking)
        let before = veil.frames
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(veil.frames, before, "в покое кадры не рисуются")
    }

    func testTrackingEndsAfterTail() throws {
        guard let veil = FogMetalVeil.make() else { throw XCTSkip("Metal недоступен") }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        veil.startTracking(tail: 0.1)
        XCTAssertTrue(veil.isTracking)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(veil.isTracking, "хвост прошёл — CADisplayLink снят")
    }

    /// Сдвинувшееся окно под подписью Apple — повод нарисовать кадр на
    /// СТОЯЩЕЙ карте, а то же самое окно — нет.
    ///
    /// Обе половины обязательны. Окно ездит вместе с разметкой и высотой
    /// листа, и дождись оно движения пальца — подпись Apple осталась бы под
    /// полной мглой ровно до него, то есть нечитаемой. А зовёт его хост на
    /// КАЖДОМ проходе разметки, и рисуй вуаль кадр на каждый такой зов —
    /// «покой без тиков» выше перестал бы быть покоем.
    func testANewAttributionWindowDrawsAFrameButTheSameOneDoesNot() throws {
        guard let veil = FogMetalVeil.make() else { throw XCTSkip("Metal недоступен") }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        // Кадр покоя уже нарисован: дальше считаем только то, что заказало
        // само окно.
        veil.invalidate()

        let box = CGRect(x: 20, y: 540, width: 120, height: 26)
        let before = veil.frames
        veil.setAttributionCarve(box)
        XCTAssertEqual(veil.frames, before + 1, "новое окно обязано доехать до экрана само")

        veil.setAttributionCarve(box)
        XCTAssertEqual(veil.frames, before + 1,
                       "то же окно второй раз — та же картинка, кадра не заказывается")

        veil.setAttributionCarve(nil)
        XCTAssertEqual(veil.frames, before + 2, "снятое окно — тоже перемена")
    }

    func testInvalidateDrawsExactlyOnce() throws {
        guard let veil = FogMetalVeil.make() else { throw XCTSkip("Metal недоступен") }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        let before = veil.frames
        veil.invalidate(); veil.invalidate()
        XCTAssertEqual(veil.frames, before + 1,
                       "одна камера — один кадр, второй invalidate без изменений ничего не рисует")
    }
}
