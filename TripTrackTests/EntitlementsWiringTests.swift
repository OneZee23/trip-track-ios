import XCTest
@testable import TripTrack

/// Оба файла entitlements — под сторожем.
///
/// До 0.8.4 файл был один и его ПЕРЕЗАПИСЫВАЛ xcodegen из `project.yml`: это
/// защищало от «выключил capability в Xcode — файл стал пустым `<dict/>`, а
/// следующий generate это закрепил». Ради CarPlay файлы разделили, а
/// `properties` у xcodegen одни на все конфигурации — значит защиту пришлось
/// забрать у него.
///
/// **CarPlay при этом НЕ ЛЕЖИТ НИ В ОДНОМ ИЗ НИХ, и это проверено опытом, а
/// не предположением.** Право `com.apple.developer.carplay-driving-task`
/// выдаёт Apple по заявке. Пока не выдано, сборка С НИМ не подписывается ни
/// для App Store, ни НА УСТРОЙСТВО — даже Debug: «Provisioning profile … doesn't
/// include the CarPlay Driving Task App capability». Apple сама пишет: «To
/// continue building for device during request processing, remove entitlement
/// and add upon approval». Владелец ставит сборку на телефон каждый день, так
/// что цена ошибки здесь — сломанная ежедневная работа.
///
/// Симулятор, вопреки ожиданию, право ТОЖЕ проверяет: без него приложение
/// исчезает с домашнего экрана CarPlay (проверено снятием кадра до и после).
/// То есть посмотреть экран машины можно только временно вписав ключ руками —
/// см. CLAUDE.md, раздел «Экран автомобиля».
///
/// Поэтому сегодня файлы ОДИНАКОВЫ, и сторож держит именно это: разъехаться
/// они имеют право ровно в тот день, когда Apple ответит.
final class EntitlementsWiringTests: XCTestCase {

    private static let carPlay = "com.apple.developer.carplay-driving-task"
    private static let appleSignIn = "com.apple.developer.applesignin"
    private static let push = "aps-environment"

    // MARK: - Release

    /// **CarPlay не лежит НИ В ОДНОМ файле, пока Apple его не выдала.**
    /// Сборка с невыданным правом не «падает потом» — она не подписывается
    /// вовсе: в Release это сорванная отправка в App Store, в Debug —
    /// сломанная установка на телефон, то есть ежедневная работа владельца.
    func testNeitherFileCarriesCarPlayUntilAppleGrantsIt() throws {
        for path in ["TripTrack/TripTrack.entitlements",
                     "TripTrack/TripTrackDebug.entitlements"] {
            let plist = try Self.plist(path)
            XCTAssertNil(plist[Self.carPlay],
                         "CarPlay просочился в \(path) — эта сборка не подпишется")
        }
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

    /// И не потерял того, что было у него до CarPlay: Debug-сборкой владелец
    /// пользуется каждый день, и вход с пушами ему нужны там не меньше.
    func testDebugKeepsSignInAndPush() throws {
        let debug = try Self.plist("TripTrack/TripTrackDebug.entitlements")
        XCTAssertEqual(debug[Self.appleSignIn] as? [String], ["Default"])
        XCTAssertEqual(debug[Self.push] as? String, "development")
    }

    // MARK: - Разница между файлами названа

    /// Сегодня состав у файлов ОДИНАКОВЫЙ. Расхождение означает, что Debug и
    /// Release разъехались по возможностям, и человек проверяет одно, а
    /// выкладывает другое.
    ///
    /// Законно разъехаться им предстоит ровно один раз — когда Apple выдаст
    /// CarPlay и он появится сначала в Debug. Тогда этот тест правят ВМЕСТЕ с
    /// решением, а не молча: ожидаемая разница вписывается сюда списком.
    func testBothFilesCarryTheSameKeys() throws {
        let release = try Self.plist("TripTrack/TripTrack.entitlements")
        let debug = try Self.plist("TripTrack/TripTrackDebug.entitlements")
        XCTAssertEqual(Set(debug.keys), Set(release.keys),
                       "состав прав разъехался: только в Debug "
                       + "\(Set(debug.keys).subtracting(release.keys).sorted()), "
                       + "только в Release "
                       + "\(Set(release.keys).subtracting(debug.keys).sorted())")
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
