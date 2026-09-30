import XCTest
@testable import TripTrack

/// Оба файла entitlements — под сторожем.
///
/// До 0.8.4 файл был один и его ПЕРЕЗАПИСЫВАЛ xcodegen из `project.yml`: это
/// защищало от «выключил capability в Xcode — файл стал пустым `<dict/>`, а
/// следующий generate это закрепил». CarPlay разделил файлы (entitlement
/// `com.apple.developer.carplay-driving-task` выдаёт Apple по заявке, и до
/// выдачи Release-сборка с ним НЕ ПОДПИШЕТСЯ), и `properties` у xcodegen одни
/// на все конфигурации — значит защиту пришлось забрать у него.
///
/// Здесь она СТРОГО БОЛЬШЕ: xcodegen следил за одним файлом и ничего не знал
/// про то, чего в нём быть НЕ должно. Читаются сами файлы с диска — тот же
/// приём, что у `SentryDSNWiringTests`, и по той же причине: вопрос ровно
/// один — доехало ли значение до артефакта.
final class EntitlementsWiringTests: XCTestCase {

    private static let carPlay = "com.apple.developer.carplay-driving-task"
    private static let appleSignIn = "com.apple.developer.applesignin"
    private static let push = "aps-environment"

    // MARK: - Release

    /// **CarPlay в Release НЕ ДОЛЖЕН ПОПАСТЬ НИКОГДА, пока Apple его не
    /// выдала.** Отправка в App Store с невыданным entitlement не «падает
    /// потом» — она не подписывается вовсе, и владелец узнаёт об этом в
    /// момент, когда собирался выкладывать.
    func testReleaseCarriesNoCarPlayUntilAppleGrantsIt() throws {
        let release = try Self.plist("TripTrack/TripTrack.entitlements")
        XCTAssertNil(release[Self.carPlay],
                     "CarPlay просочился в Release — эта сборка не подпишется")
    }

    /// Прежняя защита xcodegen: файл не имеет права опустеть. Выключенная в
    /// Xcode capability оставляла `<dict/>`, и Sign in with Apple с пушами
    /// отваливались молча.
    func testReleaseStillCarriesSignInAndPush() throws {
        let release = try Self.plist("TripTrack/TripTrack.entitlements")
        XCTAssertFalse(release.isEmpty, "файл опустел — так уже ломали вход и пуши")
        XCTAssertEqual(release[Self.appleSignIn] as? [String], ["Default"])
        XCTAssertEqual(release[Self.push] as? String, "development",
                       "архив для App Store перепишет это на production сам")
    }

    // MARK: - Debug

    /// В Debug CarPlay есть — иначе сцену не посмотреть ни в симуляторе, ни
    /// на устройстве после выдачи.
    func testDebugCarriesCarPlay() throws {
        let debug = try Self.plist("TripTrack/TripTrackDebug.entitlements")
        XCTAssertEqual(debug[Self.carPlay] as? Bool, true)
    }

    /// И не потерял того, что было у него до CarPlay: Debug-сборкой владелец
    /// пользуется каждый день, и вход с пушами ему нужны там не меньше.
    func testDebugKeepsSignInAndPush() throws {
        let debug = try Self.plist("TripTrack/TripTrackDebug.entitlements")
        XCTAssertEqual(debug[Self.appleSignIn] as? [String], ["Default"])
        XCTAssertEqual(debug[Self.push] as? String, "development")
    }

    // MARK: - Разница между файлами названа

    /// Единственное, чем файлы отличаются, — CarPlay. Любое второе расхождение
    /// означает, что Debug и Release разъехались по возможностям, и человек
    /// проверяет одно, а выкладывает другое.
    func testTheOnlyDifferenceIsCarPlay() throws {
        let release = try Self.plist("TripTrack/TripTrack.entitlements")
        let debug = try Self.plist("TripTrack/TripTrackDebug.entitlements")
        let extra = Set(debug.keys).subtracting(release.keys)
        let missing = Set(release.keys).subtracting(debug.keys)
        XCTAssertEqual(extra, [Self.carPlay],
                       "в Debug появилось что-то ещё: \(extra.sorted())")
        XCTAssertTrue(missing.isEmpty,
                      "Debug потерял ключи Release: \(missing.sorted())")
    }

    // MARK: -

    private static func plist(_ path: String) throws -> [String: Any] {
        let url = UnitGuard.repoRoot().appendingPathComponent(path)
        let data = try XCTUnwrap(try? Data(contentsOf: url),
                                 "нет файла \(path) — сторожу нечего читать")
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
        return try XCTUnwrap(parsed, "\(path) не разбирается как plist")
    }
}
