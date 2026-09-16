import XCTest
import UIKit
@testable import TripTrack

/// Ступень «средний размер» — 600 pt.
///
/// Между булавкой на карте (80 pt) и полным кадром с камеры лежала пустота,
/// и карточка предпросмотра под булавкой платила бы за неё либо мылом
/// восьмидесяти точек, либо полным разбором файла. Та же картинка первой
/// ложится в просмотрщик, поэтому спиннера там больше нет вовсе.
///
/// Заодно проверяется, что ключ кэша стал парой «имя + размер»: до этого
/// пять ступеней делили одну ячейку, и кто первым попросил, того размер
/// получали все.
@MainActor
final class PhotoPreviewTierTests: XCTestCase {

    private var tripId: UUID!
    private var filename: String!

    override func setUp() {
        super.setUp()
        tripId = UUID()
        let size = CGSize(width: 3_200, height: 2_400)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1_600, height: 1_200))
        }
        filename = PhotoStorageService.savePhoto(image, for: tripId)
    }

    /// Поля обнуляются явно — XCTest держит экземпляры до конца прогона.
    override func tearDown() {
        if let tripId { PhotoStorageService.deletePhotos(for: tripId) }
        PhotoStorageService.clearThumbnailCache()
        tripId = nil
        filename = nil
        super.tearDown()
    }

    func testPreviewTierIsSixHundredPoints() {
        XCTAssertEqual(PhotoStorageService.previewTier, 600)
        XCTAssertTrue(PhotoStorageService.thumbnailTiers.contains(600))
    }

    /// Создаётся один раз и переиспользуется: второй запрос возвращает ТОТ ЖЕ
    /// объект из памяти, а на диске рядом с ним лежит свой файл.
    func testPreviewTierIsBuiltOnceAndReused() async throws {
        let filename = try XCTUnwrap(self.filename)
        let first = try await unwrap(
            PhotoStorageService.loadThumbnail(
                filename: filename, maxSize: PhotoStorageService.previewTier))
        let second = try await unwrap(
            PhotoStorageService.loadThumbnail(
                filename: filename, maxSize: PhotoStorageService.previewTier))
        XCTAssertTrue(first === second, "вторая разборка того же файла — это и есть лишняя работа")

        let diskURL = try XCTUnwrap(PhotoStorageService.thumbnailDiskURL(
            for: filename, maxSize: PhotoStorageService.previewTier))
        XCTAssertTrue(FileManager.default.fileExists(atPath: diskURL.path))
    }

    /// Ступени не делят ни ячейку памяти, ни файл на диске.
    func testTiersDoNotCollide() async throws {
        let filename = try XCTUnwrap(self.filename)
        _ = await PhotoStorageService.loadThumbnail(
            filename: filename, maxSize: PhotoStorageService.previewTier)

        XCTAssertNotNil(PhotoStorageService.cachedThumbnail(
            filename: filename, maxSize: PhotoStorageService.previewTier))
        XCTAssertNil(
            PhotoStorageService.cachedThumbnail(filename: filename, maxSize: 80),
            "булавка в 80 pt не имеет права получить кадр в 600")

        let preview = try XCTUnwrap(PhotoStorageService.thumbnailDiskURL(
            for: filename, maxSize: PhotoStorageService.previewTier))
        let legacy = try XCTUnwrap(PhotoStorageService.thumbnailDiskURL(
            for: filename, maxSize: 150))
        XCTAssertNotEqual(preview, legacy)
        // Суффикс у ВСЕХ ступеней, включая 150: в старом `.thumbnails/<file>`
        // лежит та ступень, которая попросила ПЕРВОЙ (64, 80, 120 или 1200), и
        // читать её как 150 значило бы навсегда раздавать ленте мыло.
        XCTAssertTrue(legacy.lastPathComponent.hasSuffix("@150"))
        XCTAssertTrue(preview.lastPathComponent.hasSuffix("@600"))
    }

    /// Порядок в просмотрщике: сначала готовая ступень (она уже в памяти,
    /// значит берётся синхронно и без заглушки), потом полный кадр,
    /// разобранный СРАЗУ в размер экрана — и он крупнее ступени.
    func testViewerLoadsThumbnailFirstThenASharperFullFrame() async throws {
        let filename = try XCTUnwrap(self.filename)
        let preview = try await unwrap(
            PhotoStorageService.loadThumbnail(
                filename: filename, maxSize: PhotoStorageService.previewTier))
        // «Сразу», без ожидания: ровно этим просмотрщик и засевает страницу.
        XCTAssertNotNil(PhotoStorageService.cachedThumbnail(
            filename: filename, maxSize: PhotoStorageService.previewTier))

        let full = try await unwrap(
            PhotoStorageService.loadDownsampled(filename: filename, maxPixelSize: 2_600))
        // Сравнение в ПИКСЕЛЯХ: у полного кадра шкала экрана (иначе
        // `ZoomableImageView` посчитал бы пределы приближения втрое больше),
        // а у ступени она так и осталась единицей.
        let fullPixels = full.size.width * full.scale
        let previewPixels = preview.size.width * preview.scale
        XCTAssertGreaterThan(fullPixels, previewPixels)
        XCTAssertEqual(full.scale, UIScreen.main.scale)
        // И всё же НЕ полный файл: разбор идёт сразу в заказанный размер.
        XCTAssertLessThanOrEqual(max(fullPixels, full.size.height * full.scale), 2_600)
    }

    /// Удаление уносит и ступень, которой нет в списке.
    ///
    /// `MyMapSheet` просит `size * 3` — значение времени выполнения, никаким
    /// списком не покрываемое. А ветка диска в `loadThumbnailOutcome` стоит
    /// РАНЬШЕ проверки существования файла, поэтому пропущенная ступень
    /// продолжала бы отдавать удалённый снимок булавкой на «Атласе» вечно.
    func testDeletingAPhotoTakesAnUnlistedTierToo() async throws {
        let filename = try unwrap(self.filename)
        XCTAssertFalse(PhotoStorageService.thumbnailTiers.contains(213))
        _ = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: 213)
        let url = try XCTUnwrap(PhotoStorageService.thumbnailDiskURL(for: filename, maxSize: 213))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        PhotoStorageService.deletePhoto(filename: filename)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(PhotoStorageService.cachedThumbnail(filename: filename, maxSize: 213))
        let after = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: 213)
        XCTAssertNil(after, "удалённый снимок не имеет права жить в кэше ступени")
    }

    func testDeletingAPhotoTakesEveryTierWithIt() async throws {
        let filename = try XCTUnwrap(self.filename)
        _ = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: 80)
        _ = await PhotoStorageService.loadThumbnail(
            filename: filename, maxSize: PhotoStorageService.previewTier)

        PhotoStorageService.deletePhoto(filename: filename)

        for tier in PhotoStorageService.thumbnailTiers {
            XCTAssertNil(
                PhotoStorageService.cachedThumbnail(filename: filename, maxSize: tier),
                "ступень \(tier) пережила удаление снимка")
            if let url = PhotoStorageService.thumbnailDiskURL(for: filename, maxSize: tier) {
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    private func unwrap<T>(_ value: T?, file: StaticString = #filePath,
                           line: UInt = #line) throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
