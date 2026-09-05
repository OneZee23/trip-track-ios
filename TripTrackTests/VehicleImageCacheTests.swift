import XCTest
import UIKit
@testable import TripTrack

/// Кэш картинок машины.
///
/// Здесь заперты две причины рывка при открытии карточки, обе найденные на
/// устройстве, а не в коде.
final class VehicleImageCacheTests: XCTestCase {

    // MARK: - Подписанная ссылка не сбрасывает кэш

    /// Ссылки на чужие снимки подписаны и живут около часа: сервер отдаёт
    /// НОВУЮ подпись при каждом ответе. Совпадает только путь. Пока ключ
    /// строился по всей ссылке, кэш промахивался всегда — каждое открытие
    /// экрана означало новую загрузку по сети.
    func testSignatureChangeDoesNotChangeTheKey() throws {
        let first = try XCTUnwrap(URL(string:
            "https://r2.example/bucket/vehicle/abc.jpg?X-Amz-Signature=aaa&X-Amz-Expires=3600"))
        let second = try XCTUnwrap(URL(string:
            "https://r2.example/bucket/vehicle/abc.jpg?X-Amz-Signature=zzz&X-Amz-Expires=3600"))

        XCTAssertEqual(VehicleImageCache.remoteKey(first, 400),
                       VehicleImageCache.remoteKey(second, 400),
                       "смена подписи не должна выглядеть как другая картинка")
    }

    func testDifferentPhotosStillGetDifferentKeys() throws {
        let a = try XCTUnwrap(URL(string: "https://r2.example/bucket/vehicle/abc.jpg?s=1"))
        let b = try XCTUnwrap(URL(string: "https://r2.example/bucket/vehicle/xyz.jpg?s=1"))
        XCTAssertNotEqual(VehicleImageCache.remoteKey(a, 400), VehicleImageCache.remoteKey(b, 400))
    }

    func testSizeIsPartOfTheKey() throws {
        let url = try XCTUnwrap(URL(string: "https://r2.example/bucket/vehicle/abc.jpg"))
        XCTAssertNotEqual(VehicleImageCache.remoteKey(url, 140),
                          VehicleImageCache.remoteKey(url, 400),
                          "иначе плитка и герой перетирали бы друг друга")
    }

    // MARK: - Одна лестница размеров

    /// Экраны просили 132, 201, 504 — каждый свой размер, и ключи не совпадали
    /// ни с чем. Кэш при этом формально работал, а промахивался всегда.
    func testEveryRequestLandsOnTheLadder() {
        for requested in stride(from: CGFloat(10), through: 1200, by: 7) {
            let snapped = VehiclePhotoImage.snap(requested)
            XCTAssertTrue(VehiclePhotoImage.knownSizes.contains(snapped),
                          "\(requested) → \(snapped): не ступень лестницы")
        }
    }

    /// Прижимать вниз нельзя: копия мельче показанного размера — это мыло.
    func testSnappingNeverGoesBelowTheRequest() {
        for requested in VehiclePhotoImage.knownSizes + [1, 57, 141, 399, 401] {
            let snapped = VehiclePhotoImage.snap(requested)
            guard requested <= VehiclePhotoImage.knownSizes.last! else { continue }
            XCTAssertGreaterThanOrEqual(snapped, requested, "\(requested) прижался вниз")
        }
    }

    /// Запрос больше самой большой ступени не должен проваливаться в nil.
    func testAnOversizedRequestGetsTheLargestStep() {
        XCTAssertEqual(VehiclePhotoImage.snap(5000), VehiclePhotoImage.knownSizes.last)
    }

    // MARK: - Память отвечает синхронно

    /// Синхронный ответ — это и есть отсутствие рывка: всё асинхронное стоит
    /// как минимум кадр с заглушкой на месте фотографии.
    func testMemoryAnswersWithoutAwaiting() {
        let key = "l:test-\(UUID().uuidString).jpg@400"
        XCTAssertNil(VehicleImageCache.cached(key))
        VehicleImageCache.remember(UIImage(systemName: "car")!, key)
        XCTAssertNotNil(VehicleImageCache.cached(key), "готовая копия обязана отдаваться сразу")
        VehicleImageCache.forget()
        XCTAssertNil(VehicleImageCache.cached(key), "после сброса память должна быть пуста")
    }
}
