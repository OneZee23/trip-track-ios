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

    /// Смена стиля «Клетки» ⇄ «Туман» доезжает до экрана на СТОЯЩЕЙ карте.
    ///
    /// Латч «кадр покоя уже нарисован» ключуется тем, от чего кадр зависит, —
    /// палитрой, вырезом и, с 0.8.2, клетками. Клетки в ключ сперва не
    /// попали, и переключение стиля на неподвижной карте применялось
    /// наполовину: палитра менялась (её ключ был), а квантование оставалось
    /// прежним до первого движения пальцем. Владелец на устройстве 26 сен:
    /// «переключаешься после „клеток“ на „ночь“ и оно не успевает
    /// обновиться».
    func testSwitchingCellsDrawsAFrameOnAStandingMap() throws {
        guard let veil = FogMetalVeil.make() else { throw XCTSkip("Metal недоступен") }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        veil.invalidate()

        let before = veil.frames
        veil.setUsesCells(true)
        XCTAssertEqual(veil.frames, before + 1, "включённые клетки обязаны доехать сами")

        veil.setUsesCells(true)
        XCTAssertEqual(veil.frames, before + 1, "то же состояние второй раз кадра не стоит")

        veil.setUsesCells(false)
        XCTAssertEqual(veil.frames, before + 2, "снятые клетки — тоже перемена")
    }

    // MARK: Фон

    /// В ФОНЕ GPU НЕ ТРОГАЕМ ВОВСЕ, и это про жизнь процесса, а не про
    /// батарею: работа, посланная на GPU из фонового приложения, обрывается
    /// системой (IOAF «Insufficient Permission (to submit GPU work from
    /// background)»). TripTrack живёт в фоне часами на геолокации, и дорога
    /// сюда короткая: поездка финишировала в кармане → `.revealedLayerChanged`
    /// → перезагрузка «Атласа» → новый слой → кадр.
    ///
    /// Вторая половина не менее обязательна: пропущенный кадр НЕ считается
    /// нарисованным. Считался бы — и вернувшийся человек смотрел бы на голую
    /// карту Apple до первого движения пальцем.
    func testNoFrameIsDrawnInTheBackgroundAndTheMissedOneCatchesUpOnReturn() throws {
        let centre = NotificationCenter()
        guard let veil = FogMetalVeil.make(notifications: centre) else {
            throw XCTSkip("Metal недоступен")
        }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        var backgrounded = false
        veil.isBackgrounded = { backgrounded }
        veil.attach(map: map)
        // Кадр покоя нарисован: дальше считаем только то, что заказал фон.
        veil.invalidate()

        backgrounded = true
        let before = veil.frames
        veil.setAttributionCarve(CGRect(x: 20, y: 540, width: 120, height: 26))
        XCTAssertEqual(veil.frames, before, "в фоне за кадр не берёмся вовсе")

        // Последовательность НАСТОЯЩАЯ: на `willEnterForeground` состояние ещё
        // фоновое (в `.inactive` оно уходит ПОСЛЕ уведомления), и кадр оттуда
        // упёрся бы в собственную защиту. Пока догоняющий кадр рисовался на
        // нём, «Атлас» после кармана показывал голую карту Apple.
        centre.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertEqual(veil.frames, before,
                       "на willEnterForeground состояние ещё фоновое — за кадр не берёмся")

        backgrounded = false
        centre.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(veil.frames, before + 1,
                       "стали активными — пропущенный кадр догнан без движения камеры")
    }

    /// Кадр, который НЕ СОСТОЯЛСЯ, не считается нарисованным.
    ///
    /// `invalidate()` взводит латч «кадр покоя нарисован» ДО отрисовки, и
    /// вышедший ни с чем `draw` обязан его снять. Иначе следующий заказ — та
    /// же смена темы, то же съехавшее окно атрибуции — молчал бы, а на экране
    /// осталась бы картинка, которой там уже нет.
    ///
    /// Выходов «кадр не состоялся» два: фон и невыданный drawable. В тесте
    /// достижим первый — симулятор выдаёт drawable даже виду без окна, — но
    /// снимает латч у обоих ОДНА функция (`forgetFrame`), и проверка через
    /// фон сторожит оба.
    func testAFrameThatNeverHappenedIsNotRememberedAsDrawn() throws {
        guard let veil = FogMetalVeil.make() else { throw XCTSkip("Metal недоступен") }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        var backgrounded = false
        veil.isBackgrounded = { backgrounded }
        veil.attach(map: map)

        backgrounded = true
        veil.invalidate()
        backgrounded = false
        let before = veil.frames
        veil.invalidate()
        XCTAssertEqual(veil.frames, before + 1,
                       "несостоявшийся кадр обязан оставить заказ невыполненным")
    }

    /// `CADisplayLink` в фоне не тикает и сам, но ссылку мы снимаем: иначе
    /// первый же тик пришёлся бы ровно на возвращение — то есть кадр раньше,
    /// чем приложение снова получило право на GPU.
    func testGoingToTheBackgroundStopsTheDisplayLink() throws {
        let centre = NotificationCenter()
        guard let veil = FogMetalVeil.make(notifications: centre) else {
            throw XCTSkip("Metal недоступен")
        }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        veil.startTracking(tail: 5)
        XCTAssertTrue(veil.isTracking)

        centre.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(veil.isTracking, "ушли в фон — ссылка снята")
    }

    // MARK: Память

    /// Нехватка памяти отдаёт текстуру покрытия — единственное, что вуаль
    /// держит сверх буферов открытого мира (спека §8), — а следующий кадр
    /// заводит её заново.
    ///
    /// Вторая половина здесь тоже про латч: не сними мы память о нарисованном
    /// кадре, следующего не случилось бы до движения камеры, и «Атлас» остался
    /// бы без тумана ровно после того, как системе не хватило памяти.
    func testAMemoryWarningGivesUpTheCoverageTextureAndTheNextFrameRebuildsIt() throws {
        let centre = NotificationCenter()
        guard let veil = FogMetalVeil.make(notifications: centre) else {
            throw XCTSkip("Metal недоступен")
        }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        veil.frame = map.bounds
        veil.attach(map: map)
        try XCTSkipUnless(veil.hasCoverageTexture, "кадр не состоялся — отдавать нечего")

        centre.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertFalse(veil.hasCoverageTexture, "под нехватку памяти текстура отдаётся")

        veil.invalidate()
        XCTAssertTrue(veil.hasCoverageTexture, "и заводится заново первым же кадром")
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
