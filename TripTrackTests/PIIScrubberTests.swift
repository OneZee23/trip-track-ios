import XCTest
@testable import TripTrack

/// Держит правило «в отчёт об ошибке не уезжает ничего личного».
///
/// ПОЧЕМУ тестом, а не глазами: то, что чистит `SentryService`, кладут в
/// событие не мы, а сам SDK — автоматикой, которая включена по умолчанию
/// и меняется от версии к версии. Проверить это на живом Sentry можно
/// только уронив приложение с чужим `accountId` в URL, то есть уже после
/// утечки.
final class PIIScrubberTests: XCTestCase {

    // MARK: - URL

    func testURLKeepsShapeAndDropsAccountId() {
        let out = PIIScrubber.redactURL("https://api.trip-track.app/users/8B0F1C2E-3D4A-5B6C-7D8E-9F0A1B2C3D4E/trips")
        XCTAssertEqual(out, "https://api.trip-track.app/users/<id>/trips")
    }

    func testURLDropsQueryEntirely() {
        // Курсор ленты по формату — `дата|id поездки`, то есть «кто и
        // когда ездил» прямо в query-строке.
        let out = PIIScrubber.redactURL(
            "https://api.trip-track.app/users/abc123/trips?limit=20&cursor=2026-09-01T10%3A00%3A00Z%7C4F3E")
        XCTAssertEqual(out, "https://api.trip-track.app/users/<id>/trips")
        XCTAssertFalse(out.contains("cursor"))
        XCTAssertFalse(out.contains("2026"))
    }

    func testURLDropsFragmentAndCredentials() {
        let out = PIIScrubber.redactURL("https://user:secret@api.trip-track.app/auth/me#token")
        XCTAssertFalse(out.contains("secret"))
        XCTAssertFalse(out.contains("token"))
        XCTAssertEqual(out, "https://api.trip-track.app/auth/me")
    }

    func testURLKeepsPlainRouteWords() {
        // «Какой эндпоинт упал» — половина ценности отчёта, она остаётся.
        XCTAssertEqual(PIIScrubber.redactURL("https://api.trip-track.app/auth/notification-prefs/update"),
                       "https://api.trip-track.app/auth/notification-prefs/update")
        XCTAssertEqual(PIIScrubber.redactURL("https://api.trip-track.app/sync/pull"),
                       "https://api.trip-track.app/sync/pull")
    }

    func testURLMasksUnknownSegmentsByDefault() {
        // Сегмент с цифрами или длинный — прячется, даже если это не UUID:
        // новый эндпоинт с ключом в пути не должен ждать правки этого файла.
        XCTAssertEqual(PIIScrubber.redactURL("https://cdn.example.com/photos/a1b2c3d4e5f6"),
                       "https://cdn.example.com/photos/<id>")
        XCTAssertEqual(PIIScrubber.redactURL("https://cdn.example.com/x/averylongsegmentwithoutdigitsatall"),
                       "https://cdn.example.com/x/<id>")
    }

    func testURLPresignedPhotoLinkLosesSignature() {
        let out = PIIScrubber.redactURL(
            "https://r2.example.com/trip-photos/9F0A1B2C.jpg?X-Amz-Signature=deadbeef&X-Amz-Expires=3600")
        XCTAssertFalse(out.contains("X-Amz-Signature"))
        XCTAssertFalse(out.contains("deadbeef"))
    }

    func testUnparsableURLBecomesMarkerNotPassthrough() {
        XCTAssertEqual(PIIScrubber.redactURL("не url вовсе"), PIIScrubber.redactedMarker)
        // Относительный путь без хоста — тоже не отдаём как есть.
        XCTAssertEqual(PIIScrubber.redactURL("/users/8B0F/trips"), PIIScrubber.redactedMarker)
    }

    // MARK: - Словари

    func testTokensAndIdentityAreRedacted() {
        let out = PIIScrubber.redact(dict: [
            "accessToken": "eyJhbGciOi",
            "refreshToken": "r-123",
            "email": "driver@example.com",
            "displayName": "Иван",
            "statusCode": 500,
        ])
        XCTAssertEqual(out["accessToken"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(out["refreshToken"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(out["email"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(out["displayName"] as? String, PIIScrubber.redactedMarker)
        // Не персональное остаётся — иначе отчёт нечитаем.
        XCTAssertEqual(out["statusCode"] as? Int, 500)
    }

    func testHomeCoordinatesAreRedacted() {
        let out = PIIScrubber.redact(dict: ["homeLatitude": 45.03, "homeLongitude": 38.97])
        XCTAssertEqual(out["homeLatitude"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(out["homeLongitude"] as? String, PIIScrubber.redactedMarker)
    }

    func testNestedDictionariesAndArraysAreWalked() {
        let out = PIIScrubber.redact(dict: [
            "response": ["headers": ["authorization": "Bearer x", "accessToken": "t"]],
            "queue": [["identityToken": "id-token"], ["op": "upload"]],
        ])
        let response = out["response"] as? [String: Any]
        let headers = response?["headers"] as? [String: Any]
        XCTAssertEqual(headers?["accessToken"] as? String, PIIScrubber.redactedMarker)

        let queue = out["queue"] as? [Any]
        let first = queue?.first as? [String: Any]
        XCTAssertEqual(first?["identityToken"] as? String, PIIScrubber.redactedMarker)
        let second = queue?.last as? [String: Any]
        XCTAssertEqual(second?["op"] as? String, "upload")
    }

    func testScrubberListMatchesAPILoggerList() {
        // Один список на обе диагностические поверхности — иначе они
        // разъедутся молча.
        XCTAssertTrue(PIISensitiveKeys.all.contains("accessToken"))
        XCTAssertTrue(PIISensitiveKeys.all.contains("url"))
        XCTAssertTrue(PIISensitiveKeys.all.contains("homeLatitude"))
    }

    /// Ключ в UserDefaults лежит с префиксом, а имя поля то же — строгое
    /// равенство пропускало бы ровно тот дамп настроек, ради которого
    /// координаты дома в списке и стоят.
    func testPrefixedUserDefaultsKeyIsRedacted() {
        let out = PIIScrubber.redact(dict: [
            "com.triptrack.settings.homeLatitude": 45.03,
            "com.triptrack.settings.homeLongitude": 38.98,
            "com.triptrack.settings.appLanguage": "ru",
        ])
        XCTAssertEqual(out["com.triptrack.settings.homeLatitude"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(out["com.triptrack.settings.homeLongitude"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(out["com.triptrack.settings.appLanguage"] as? String, "ru",
                       "безобидная настройка не должна прятаться")
    }

    /// Регистр приходит разный: сервер пишет camelCase, SDK — как получится.
    func testMatchIsCaseInsensitive() {
        XCTAssertTrue(PIISensitiveKeys.matches("AccessToken"))
        XCTAssertTrue(PIISensitiveKeys.matches("user_email"))
        XCTAssertFalse(PIISensitiveKeys.matches("tokenizer"),
                       "совпадать должно ИМЯ поля, а не подстрока внутри чужого слова")
    }

    // MARK: - Контекст, который кладёт сам SDK

    /// `device_app_hash` — производная от Apple `identifierForVendor`, и
    /// кладёт её в контекст `app` сам Sentry, без единой нашей строки. Рядом
    /// в том же событии стоит `user.id`, то есть «кто» и «с какой установки»
    /// склеиваются без нашего участия.
    ///
    /// ПОЧЕМУ тестом по СЛОВАРЮ, а не по глазам: чистка контекста в
    /// `SentryService.scrub(event:)` идёт ровно этим проходом
    /// (`context.mapValues { PIIScrubber.redact(dict: $0) }`), а форма
    /// контекста — не наша, она меняется от версии SDK. Здесь повторена
    /// именно она.
    func testSDKDeviceAppHashIsRedactedFromAppContext() {
        let sdkContext: [String: [String: Any]] = [
            "app": [
                "app_identifier": "app.trip-track.ios",
                "app_version": "0.6.6",
                "app_build": "58",
                "device_app_hash": "7b1c9a0f4e2d6853a1b0c9d8e7f60514",
            ],
            "device": ["model": "iPhone15,2", "free_memory": 812_345_678],
        ]

        let out = sdkContext.mapValues { PIIScrubber.redact(dict: $0) }
        let app = out["app"]

        XCTAssertEqual(app?["device_app_hash"] as? String, PIIScrubber.redactedMarker)
        XCTAssertEqual(app?["app_version"] as? String, "0.6.6",
                       "версия сборки — половина ценности отчёта, она остаётся")
        XCTAssertEqual((out["device"]?["model"]) as? String, "iPhone15,2")

        // Значение не должно пережить чистку НИГДЕ в событии: событие
        // уезжает целиком, а не по одному полю.
        XCTAssertFalse("\(out)".contains("7b1c9a0f4e2d6853a1b0c9d8e7f60514"))
    }

    /// Имя пришло из SDK в snake_case, а список у нас в основном camelCase —
    /// проверяем, что оно опознаётся и само, и с префиксом.
    func testDeviceAppHashIsInTheSharedList() {
        XCTAssertTrue(PIISensitiveKeys.all.contains("device_app_hash"))
        XCTAssertTrue(PIISensitiveKeys.matches("device_app_hash"))
        XCTAssertTrue(PIISensitiveKeys.matches("contexts.device_app_hash"))
    }
}
