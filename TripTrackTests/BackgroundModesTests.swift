import XCTest
@testable import TripTrack

/// Фоновые режимы — под сторожем, и куплен он ОТКАЗОМ РЕВЬЮ.
///
/// 30 сентября 2026 Apple отклонила 0.8.2 по гайдлайну 2.5.4: «The app declares
/// support for bluetooth-central in the UIBackgroundModes key in your Info.plist
/// but we are unable to locate any Bluetooth Low Energy functionality».
/// Апелляции не потребовалось — они были правы: магнитола это КЛАССИЧЕСКИЙ
/// Bluetooth (A2DP/HFP), и BLE-сканирование её не видит никогда, о чём прямо
/// написано в `AudioRouteDetector.currentBluetoothOutputName`. Машину ловит
/// аудио-маршрут, которому фоновый режим не нужен.
///
/// Цена такого отказа — ЦИКЛ РЕВЬЮ, а не правка строки: версия уезжает в
/// «Rejected», и вместе с ней встаёт всё, что было готово. Поймать это сборкой
/// нельзя, поведением тоже: лишний режим ничего не ломает на телефоне, он
/// ломает только приёмку.
///
/// Поэтому правило здесь одно и оно в белом списке: каждый объявленный режим
/// назван вместе с ПРИЧИНОЙ, и причина написана словами. Появился новый —
/// строка в этом тесте обязана быть видимым решением в диффе, а не тихой
/// правкой plist (тот же приём, что у allowlist `UnitsDisciplineTests`).
final class BackgroundModesTests: XCTestCase {

    /// Режимы, которые приложение имеет право объявлять, и за что.
    ///
    /// Заводя сюда строку, спроси себя то же, что спросит ревьюер: где эту
    /// функцию ВИДНО и как её проверить руками на устройстве. Не можешь
    /// показать — режим объявлять нельзя.
    private static let allowed: [String: String] = [
        "location": """
            Запись поездки продолжается, когда телефон в кармане, а приложение \
            свёрнуто. Это и есть смысл приложения; проверяется ревьюером за \
            минуту — начать запись и свернуть.
            """
    ]

    private func declaredModes() throws -> [String] {
        let url = UnitGuard.repoRoot().appendingPathComponent("TripTrack/Info.plist")
        let data = try XCTUnwrap(try? Data(contentsOf: url), "нет TripTrack/Info.plist")
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
            "Info.plist не разбирается")
        return (plist["UIBackgroundModes"] as? [String]) ?? []
    }

    /// Ни одного режима сверх белого списка.
    func testEveryDeclaredBackgroundModeIsJustified() throws {
        let modes = try declaredModes()
        XCTAssertFalse(modes.isEmpty, "режимов не осталось вовсе — фоновая запись сломана?")
        for mode in modes {
            XCTAssertNotNil(
                Self.allowed[mode],
                "фоновый режим «\(mode)» объявлен, но не назван в белом списке "
                + "`BackgroundModesTests.allowed` вместе с причиной. Лишний режим — "
                + "это отказ ревью 2.5.4 и потерянный цикл, а не предупреждение.")
        }
    }

    /// `bluetooth-central` — ИМЕННО ТОТ, за который отклонили. Отдельным
    /// тестом, а не только белым списком: он назван в отказе буквально, и
    /// вернуть его «на всякий случай» соблазнительнее всего.
    func testBluetoothCentralStaysOutAfterTheRejection() throws {
        XCTAssertFalse(
            try declaredModes().contains("bluetooth-central"),
            "`bluetooth-central` вернулся в UIBackgroundModes. За него уже "
            + "отклонили 0.8.2 (2.5.4, 30 сен 2026): BLE не видит магнитолу, "
            + "её ловит аудио-маршрут. Нужен фоновый BLE — сначала должна "
            + "появиться функция, которую ревьюер сможет найти руками.")
    }

    /// Восстановление состояния Core Bluetooth работает ТОЛЬКО с этим режимом.
    ///
    /// Читается по исходнику: `CBCentralManagerOptionRestoreIdentifierKey` без
    /// `bluetooth-central` — это просьба к системе о праве, которого у
    /// приложения нет. Поведением не задать: система просто молчит.
    func testStateRestorationIsGoneWithTheMode() throws {
        let url = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/Services/BluetoothDetector.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // В комментариях упоминать можно — там объяснено, почему его нет.
        let code = source
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("CBCentralManagerOptionRestoreIdentifierKey"),
                       "восстановление состояния вернулось без фонового режима")
        XCTAssertFalse(code.contains("willRestoreState"),
                       "обработчик восстановления вернулся без фонового режима")
    }
}
