import CoreLocation
import XCTest
@testable import TripTrack

/// 36а/36б/36в: подписка кончилась, пока лист был открыт и заполнен.
///
/// Раньше такого пути не существовало — в лист нельзя было попасть без PRO.
/// Теперь можно: гейт спрашивается ЗАНОВО в момент записи (и правильно
/// делает), и человек не должен потерять набранный маршрут.
@MainActor
final class ManualTripPaywallReturnTests: XCTestCase {

    private let from = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
    private let to = CLLocationCoordinate2D(latitude: 44.6300, longitude: 39.1300)

    private func filled() -> ManualTripModel {
        let model = ManualTripModel()
        model.from = ManualTripPoint(name: "Краснодар", coordinate: from)
        model.to = ManualTripPoint(name: "Горячий Ключ", coordinate: to)
        model.via = [ManualTripPoint(name: "Заправка", coordinate: from)]
        model.startDate = Date().addingTimeInterval(-6 * 3600)
        model.duration = 3 * 3600
        return model
    }

    /// Отказ по подписке и отказ базы — РАЗНЫЕ карточки с разными кнопками.
    ///
    /// «Повторить» у человека с кончившейся подпиской ничего не изменит, он
    /// будет жать её, пока не устанет; «Продлить» у отказа базы уведёт его
    /// покупать то, что у него и так есть.
    func testTheTwoRefusalsOfferDifferentActions() {
        XCTAssertEqual(ManualTripCreateError.noAccess.action, .renew)
        XCTAssertEqual(ManualTripCreateError.notSaved.action, .retry)
        XCTAssertNotEqual(ManualTripCreateError.noAccess.action,
                          ManualTripCreateError.notSaved.action)
    }

    /// 36б: пейвол ушёл — модель та же, набранное на месте.
    ///
    /// Держит решение §12.2: пейвол показывается ВТОРЫМ листом поверх, и
    /// `@StateObject` под ним жив. Подмени мы содержимое хоста — модель
    /// умерла бы вместе с точками, и пришлось бы писать восстановление
    /// состояния, которого иначе не нужно.
    func testModelSurvivesThePaywall() {
        let model = filled()
        let before = (model.from?.name, model.to?.name, model.via.count, model.duration)
        model.failForTesting(.noAccess)

        // Ровно то, что делает кнопка «Продлить»: карточку убрали, пейвол
        // открыли поверх. Лист не пересоздаётся.
        model.clearCreateError()

        XCTAssertEqual(model.from?.name, before.0)
        XCTAssertEqual(model.to?.name, before.1)
        XCTAssertEqual(model.via.count, before.2)
        XCTAssertEqual(model.duration, before.3)
        XCTAssertNil(model.createError, "карточка отказа ушла")
    }

    /// 36в: отменил покупку — карточка «PRO закончился» на месте, «Продлить»
    /// снова активна. Набранное тоже на месте.
    func testCancellingThePurchaseLeavesTheErrorCard() {
        let model = filled()
        model.failForTesting(.noAccess)
        XCTAssertEqual(model.createError, .noAccess)
        XCTAssertEqual(model.createError?.action, .renew)
        XCTAssertEqual(model.from?.name, "Краснодар")
        XCTAssertEqual(model.via.count, 1)
    }

    /// Автозаписи после покупки нет: «Записать» человек нажимает сам.
    ///
    /// Иначе зашедший на пейвол из листа получил бы поездку одним нажатием,
    /// которого он не делал.
    ///
    /// Сторожится ЧТЕНИЕМ ИСХОДНИКА, а не константой. Финальное ревью
    /// справедливо назвало прежнюю проверку декоративной: константу сам вид не
    /// читает, и `XCTAssertFalse` на ней утверждал, что константа равна себе —
    /// то есть не поймал бы никакой регрессии вовсе. Правило же конкретное:
    /// закрытие пейвола, открытого поверх листа, не имеет права звать
    /// `create()`.
    func testBuyingDoesNotRecordByItself() {
        XCTAssertFalse(ManualTripSheet.recordsAutomaticallyAfterPurchase,
                       "решение записано константой — она документирует его")

        let source = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/Views/ManualTrip/ManualTripSheet.swift")
        let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
        XCTAssertFalse(text.isEmpty, "исходника рядом с тестом нет — сторожу нечего читать")

        guard let sheetRange = text.range(of: ".sheet(isPresented: $paywallOverSheet)") else {
            XCTFail("пейвол больше не открывается поверх листа — правило переехало, "
                    + "и сторож обязан переехать за ним")
            return
        }
        // Шестьсот знаков после `.sheet(` — с запасом на всё замыкание
        // презентации (сейчас в нём четыре строки). Считать скобки тут не
        // надо: вопрос один — не зовётся ли `create()` рядом с показом
        // пейвола.
        let closure = text[sheetRange.lowerBound...].prefix(600)
        XCTAssertFalse(closure.contains("create()"),
                       "закрытие пейвола зовёт create() — поездка запишется сама, "
                       + "без нажатия «Записать»")
    }

    /// Слова у карточек разные на всех тринадцати языках, и ни одна пара не
    /// совпадает: общий текст свёл бы два разных случая в один.
    func testTheRefusalCopyDiffersInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            let proTitle = AppStrings.manualFailedProTitle(lang)
            let dbTitle = AppStrings.manualFailedDbTitle(lang)
            let proText = AppStrings.manualFailedProText(lang)
            let dbText = AppStrings.manualFailedDbText(lang)
            for text in [proTitle, dbTitle, proText, dbText] {
                XCTAssertFalse(text.isEmpty, lang.rawValue)
                XCTAssertFalse(text.contains("{"), "\(lang.rawValue): «\(text)»")
            }
            XCTAssertNotEqual(proTitle, dbTitle, lang.rawValue)
            XCTAssertNotEqual(proText, dbText, lang.rawValue)
        }
    }

    /// Строка честности стоит под кнопкой и на всех языках говорит про
    /// награды: вписанная поездка даёт километры, но не опыт и не значки
    /// (правило 0.8.0). Узнать об этом ПОСЛЕ покупки хуже, чем не купить.
    func testTheHonestyLineIsThereInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            let line = AppStrings.manualHonesty(lang)
            XCTAssertFalse(line.isEmpty, lang.rawValue)
            XCTAssertFalse(line.contains("{"), lang.rawValue)
        }
    }
}
