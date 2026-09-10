import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UIKit
@testable import TripTrack

/// Метаданные снимка живут ровно до сохранения.
///
/// `PhotoStorageService.savePhoto` пересжимает кадр в свой JPEG, и файл в
/// Documents уже не помнит ни времени съёмки, ни координаты. Значит спросить
/// надо в момент добавления — иначе `TripPhotoPlacement` не поставит кадр на
/// карту вообще, а `TripCheckpointPhotos` не привяжет его к отметке. Ровно это
/// и происходило со снимком, приложенным на экране финиша: он шёл в базу
/// голым.
///
/// Половина проверок здесь — про молчание. Кадр без EXIF обязан отдать пустоту
/// и не додумать ничего: время, взятое не оттуда, увозит снимок за сотню
/// километров от места съёмки, и по карте этого не видно.
final class PhotoMetadataTests: XCTestCase {

    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var tripId: UUID!
    /// Каталог снимков общий и переживает прогон — убираем за собой руками.
    private var madeDirs: [URL] = []

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        tripId = UUID()
        trip.id = tripId
        trip.startDate = Date(timeIntervalSince1970: 1_780_000_000)
        trip.endDate = Date(timeIntervalSince1970: 1_780_003_600)
        try? ctx.save()
    }

    override func tearDown() {
        for dir in madeDirs { try? FileManager.default.removeItem(at: dir) }
        madeDirs = []
        repo = nil
        pc = nil
        tripId = nil
        super.tearDown()
    }

    // MARK: - Настоящий JPEG

    /// Кадр собирается настоящим: ImageIO пишет EXIF, ImageIO же его и читает
    /// — подсунутый словарь проверял бы наши намерения, а не работу.
    private func jpeg(exif: [CFString: Any]? = nil, gps: [CFString: Any]? = nil) -> Data {
        let ctx = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let cg = ctx.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if let exif { props[kCGImagePropertyExifDictionary] = exif }
        if let gps { props[kCGImagePropertyGPSDictionary] = gps }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private static let shotStamp = "2026:09:10 14:23:05"

    /// То же время, посчитанное календарём, а не тем же форматтером, что в коде.
    private static func shotMoment(in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(
            year: 2026, month: 9, day: 10, hour: 14, minute: 23, second: 5))!
    }

    private static let exifWithTime: [CFString: Any] = [
        kCGImagePropertyExifDateTimeOriginal: shotStamp
    ]

    private static let gpsNovorossiysk: [CFString: Any] = [
        kCGImagePropertyGPSLatitude: 44.7239,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 37.7686,
        kCGImagePropertyGPSLongitudeRef: "E",
    ]

    // MARK: - Разбор

    /// Кадр с EXIF отдаёт и время, и координату.
    func testAFrameWithExifGivesUpItsTimeAndPlace() {
        let meta = PhotoMetadata.read(
            fromImageData: jpeg(exif: Self.exifWithTime, gps: Self.gpsNovorossiysk))

        XCTAssertEqual(meta.capturedAt, Self.shotMoment(in: .current))
        XCTAssertEqual(meta.latitude ?? 0, 44.7239, accuracy: 0.0001)
        XCTAssertEqual(meta.longitude ?? 0, 37.7686, accuracy: 0.0001)
        XCTAssertFalse(meta.isEmpty)
    }

    /// Кадр без EXIF молчит. Это и есть правильный ответ: догадка тут дороже
    /// пустоты.
    func testAFrameWithoutExifInventsNothing() {
        let meta = PhotoMetadata.read(fromImageData: jpeg())

        XCTAssertTrue(meta.isEmpty)
        XCTAssertNil(meta.capturedAt)
        XCTAssertNil(meta.latitude)
        XCTAssertNil(meta.longitude)
    }

    /// Геометки выключены у многих, а мессенджер срезает их всегда. Время при
    /// этом остаётся — и его хватает, чтобы поставить кадр по треку.
    func testTimeWithoutAPlaceStaysTimeWithoutAPlace() {
        let meta = PhotoMetadata.read(fromImageData: jpeg(exif: Self.exifWithTime))

        XCTAssertEqual(meta.capturedAt, Self.shotMoment(in: .current))
        XCTAssertNil(meta.latitude)
        XCTAssertNil(meta.longitude)
    }

    /// Полушарие живёт отдельной буквой: забыть про неё — увезти кадр из
    /// Кейптауна в Египет.
    func testSouthAndWestComeBackSigned() {
        let meta = PhotoMetadata.read(fromImageData: jpeg(gps: [
            kCGImagePropertyGPSLatitude: 33.9249,
            kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 18.4241,
            kCGImagePropertyGPSLongitudeRef: "W",
        ]))

        XCTAssertEqual(meta.latitude ?? 0, -33.9249, accuracy: 0.0001)
        XCTAssertEqual(meta.longitude ?? 0, -18.4241, accuracy: 0.0001)
    }

    /// Ровный ноль в обеих координатах — незаполненное поле, а не Гвинейский
    /// залив.
    func testAZeroedGPSDictionaryIsNoPlaceAtAll() {
        let meta = PhotoMetadata.read(fromImageData: jpeg(exif: Self.exifWithTime, gps: [
            kCGImagePropertyGPSLatitude: 0.0,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 0.0,
            kCGImagePropertyGPSLongitudeRef: "E",
        ]))

        XCTAssertNotNil(meta.capturedAt)
        XCTAssertNil(meta.latitude)
        XCTAssertNil(meta.longitude)
    }

    /// Не картинка — не разбор. Молча и без падения.
    func testGarbageBytesAreNotAPhoto() {
        XCTAssertTrue(PhotoMetadata.read(fromImageData: Data([0x01, 0x02, 0x03])).isEmpty)
        XCTAssertTrue(PhotoMetadata.read(fromImageData: Data()).isEmpty)
    }

    /// Съёмка со смещением зоны — момент абсолютный, зона телефона ни при чём.
    ///
    /// Тег есть далеко не у всех камер, поэтому проверяется отдельно от
    /// основного случая: без него берётся зона телефона, и это правильно —
    /// снимок добавляют к поездке, которую только что проехали.
    func testAnExplicitZoneOffsetWins() {
        let meta = PhotoMetadata.read(fromImageData: jpeg(exif: [
            kCGImagePropertyExifDateTimeOriginal: Self.shotStamp,
            kCGImagePropertyExifOffsetTimeOriginal: "+03:00",
        ]))

        XCTAssertEqual(meta.capturedAt, Self.shotMoment(in: TimeZone(secondsFromGMT: 3 * 3600)!))
    }

    // MARK: - Цепочка целиком

    /// Экран финиша: байты → метаданные → база → место на карте.
    ///
    /// Проверяется именно то, что было сломано: снимок доезжает до карты, а не
    /// теряет поля по дороге. Поля читаются ИЗ БАЗЫ, а не из возврата
    /// `addPhoto`, — иначе тест не заметил бы, что в CoreData ушла пустота.
    func testAPhotoAddedFromTheFinishScreenLandsOnTheMap() throws {
        let data = jpeg(exif: Self.exifWithTime, gps: Self.gpsNovorossiysk)
        let meta = PhotoMetadata.read(fromImageData: data)
        let image = try XCTUnwrap(UIImage(data: data))
        rememberPhotoDir()

        XCTAssertNotNil(repo.addPhoto(
            to: tripId, image: image, caption: nil,
            capturedAt: meta.capturedAt,
            latitude: meta.latitude, longitude: meta.longitude))

        let stored = try XCTUnwrap(repo.fetchTripDetail(id: tripId)?.photos.first)
        XCTAssertEqual(stored.capturedAt, meta.capturedAt)

        let placed = TripPhotoPlacement.place([stored], on: [])
        XCTAssertEqual(placed.first?.source, .photo)
        XCTAssertEqual(placed.first?.latitude ?? 0, 44.7239, accuracy: 0.0001)
    }

    /// Тот же путь у кадра без геометки: место считается по треку. Это самый
    /// частый случай — координаты в снимках нет у большинства.
    func testAPhotoWithOnlyATimeLandsOnTheTrack() throws {
        let data = jpeg(exif: Self.exifWithTime)
        let meta = PhotoMetadata.read(fromImageData: data)
        let image = try XCTUnwrap(UIImage(data: data))
        let shot = try XCTUnwrap(meta.capturedAt)
        rememberPhotoDir()

        XCTAssertNotNil(repo.addPhoto(
            to: tripId, image: image, caption: nil,
            capturedAt: meta.capturedAt,
            latitude: meta.latitude, longitude: meta.longitude))

        let stored = try XCTUnwrap(repo.fetchTripDetail(id: tripId)?.photos.first)
        let points = (0...100).map { t in
            TrackPoint(latitude: 45.0 + Double(t) * 0.001, longitude: 38.9, speed: 10,
                       timestamp: shot.addingTimeInterval(Double(t) - 50))
        }

        let placed = TripPhotoPlacement.place([stored], on: points)
        XCTAssertEqual(placed.first?.source, .track)
        XCTAssertEqual(placed.first?.latitude ?? 0, 45.05, accuracy: 0.0011)
    }

    /// Настоящий `savePhoto` кладёт файл в Documents — каталог этой поездки
    /// уносим в tearDown.
    private func rememberPhotoDir() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TripPhotos", isDirectory: true)
            .appendingPathComponent(tripId.uuidString, isDirectory: true)
        madeDirs.append(dir)
    }
}
