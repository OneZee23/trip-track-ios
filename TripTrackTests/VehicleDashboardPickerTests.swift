import XCTest
@testable import TripTrack

/// Строка «Приборка» и лист за ней: слова, которыми выбор показывается
/// человеку, и граница, за которую этот выбор не имеет права выйти.
///
/// До 0.6.7 менять единицу машины было нечем, и настройка существовала только
/// в базе. Интерфейс, который её открывает, добавляет ровно две новые
/// опасности — обе здесь:
///
/// 1. **Имя выбора врёт.** Три варианта, у которых в каком-то языке совпали
///    два названия, — это список, в котором нельзя выбрать; а подсказка под
///    полем ввода, говорящая «Как в приложении», не отвечает на единственный
///    вопрос, который у поля задают: «мили или километры я сейчас набираю».
/// 2. **Выбор уезжает шире машины.** Ровно этим был живой баг, который 0.6.7
///    чинила: экран КОНКРЕТНОЙ машины писал в настройку аккаунта, и она
///    уходила на сервер и на второй телефон. Дверь закрыта у объёма
///    (`VehicleConsumptionUnitTests`), и она же обязана быть закрыта у
///    расстояния — иначе новый пикер откроет её заново с другой стороны.
///
/// Про награды — соседний файл `VehicleUnitsStayOutOfRewardsTests`: сюда
/// единица машины приходит словом, туда не приходит вовсе.
final class VehicleDashboardPickerTests: XCTestCase {

    // MARK: - Имена вариантов

    /// Три варианта — три РАЗНЫХ имени, во всех тринадцати языках и у машины
    /// с баком и без.
    ///
    /// Список, в котором два варианта названы одинаково, невозможно выбрать
    /// глазами: значок слева показывает разрешённую единицу и у «Как в
    /// приложении» СОВПАДАЕТ с одним из двух других (это решение, см.
    /// `DashboardUnits.badge`), то есть различает варианты только имя.
    /// Ошибиться здесь легко именно в таблицах: строки «Километры и литры» и
    /// «Мили и галлоны» переводятся подряд и копируются одна из другой.
    func testEveryLanguageNamesAllThreeChoicesDifferently() {
        for lang in LanguageManager.Language.allCases {
            for burnsFuel in [true, false] {
                let names = DashboardUnits.allCases.map { $0.label(lang, burnsFuel: burnsFuel) }

                for (unit, name) in zip(DashboardUnits.allCases, names) {
                    XCTAssertFalse(
                        name.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(lang.rawValue): у варианта «\(unit.rawValue)» нет имени")
                }
                XCTAssertEqual(
                    Set(names).count, names.count,
                    "\(lang.rawValue), бак=\(burnsFuel): имена вариантов совпали — \(names)")
            }
        }
    }

    /// У велосипеда в списке нет литров.
    ///
    /// Топливные карточки формы спрятаны по `VehicleType.burnsFuel`, и
    /// предлагать там выбор «Километры и литры» значит называть то, чего у
    /// этой машины не бывает. Слово берётся то же, которым подписан выбор
    /// единиц ПРИЛОЖЕНИЯ, — новых строк на это не заводилось.
    func testAVehicleWithNoTankIsNeverOfferedLitres() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertEqual(DashboardUnits.metric.label(lang, burnsFuel: false),
                           DistanceUnit.km.labelFull(lang))
            XCTAssertEqual(DashboardUnits.imperial.label(lang, burnsFuel: false),
                           DistanceUnit.miles.labelFull(lang))

            XCTAssertNotEqual(DashboardUnits.metric.label(lang, burnsFuel: false),
                              DashboardUnits.metric.label(lang, burnsFuel: true),
                              "\(lang.rawValue): у машины без бака имя не изменилось")
        }
        // «Как в приложении» одинаково у обоих: это ответ про ЧЕЙ выбор, и
        // бак к нему отношения не имеет.
        XCTAssertEqual(DashboardUnits.app.label(.ru, burnsFuel: false),
                       DashboardUnits.app.label(.ru, burnsFuel: true))
    }

    // MARK: - Подсказка у поля

    /// Живая строка под полем ввода НИКОГДА не говорит «Как в приложении».
    ///
    /// У поля ручного пробега вопрос ровно один — в чём набирать, — и «как в
    /// приложении» на него не отвечает: это ответ на другой вопрос, чей это
    /// выбор. Поэтому `resolvedLabel` разворачивает `app` в ту единицу, в
    /// которую он разрешился, и совпадает с именем конкретного варианта.
    func testTheFieldHintNeverSaysSameAsApp() {
        for lang in LanguageManager.Language.allCases {
            let asApp = DashboardUnits.app.label(lang, burnsFuel: true)
            for appUnit in DistanceUnit.allCases {
                for units in DashboardUnits.allCases {
                    let shown = units.resolvedLabel(lang, app: appUnit, burnsFuel: true)
                    XCTAssertNotEqual(shown, asApp,
                                      "\(lang.rawValue): подсказка у поля назвала чужой выбор")
                }
            }
        }

        // И разворачивается он именно туда, куда разрешился, а не «всегда в
        // километры»: американец с километровой тойотой обязан прочитать под
        // полем «Километры и литры».
        XCTAssertEqual(
            DashboardUnits.app.resolvedLabel(.ru, app: .miles, burnsFuel: true),
            DashboardUnits.imperial.label(.ru, burnsFuel: true))
        XCTAssertEqual(
            DashboardUnits.metric.resolvedLabel(.ru, app: .miles, burnsFuel: true),
            DashboardUnits.metric.label(.ru, burnsFuel: true))
    }

    /// Подсказка называет ТУ ЖЕ единицу, которой разбирается поле.
    ///
    /// Это единственное место версии, где ошибка с единицей попадает в БАЗУ
    /// (`OdometerField`), и подпись рядом с ним — не украшение, а обещание.
    /// Разойтись они могут молча: подсказку однажды переведут на единицу
    /// человека «чтобы было как везде», и приложение начнёт называть мили,
    /// разбирая километры.
    func testTheHintNamesTheUnitTheFieldIsActuallyParsedIn() {
        for appUnit in DistanceUnit.allCases {
            for units in DashboardUnits.allCases {
                let parsing = units.resolved(app: appUnit)
                let named = units.resolvedLabel(.ru, app: appUnit, burnsFuel: true)

                XCTAssertEqual(named, (parsing == .miles ? DashboardUnits.imperial : .metric)
                    .label(.ru, burnsFuel: true))

                // Сто единиц показа — это сто километров у метрической панели
                // и 160.9 у мильной. Число здесь затем, чтобы имя и разбор
                // проверялись ОДНИМ утверждением: разъехаться им нечем.
                let stored = OdometerField.storedKm("100", unit: parsing)
                XCTAssertEqual(stored ?? 0,
                               parsing == .miles ? 160.9344 : 100,
                               accuracy: 0.000_1)
            }
        }
    }

    /// Значок показывает РАЗРЕШЁННУЮ единицу — в том числе у «Как в
    /// приложении», где он и повторяет один из двух других. Повтор осознан:
    /// это молчаливый ответ на «а что у меня сейчас в приложении?».
    func testTheBadgeShowsTheUnitTheChoiceResolvesTo() {
        XCTAssertEqual(DashboardUnits.app.badge(.en, app: .miles),
                       DashboardUnits.imperial.badge(.en, app: .miles))
        XCTAssertEqual(DashboardUnits.app.badge(.en, app: .km),
                       DashboardUnits.metric.badge(.en, app: .km))
        XCTAssertNotEqual(DashboardUnits.metric.badge(.en, app: .miles),
                          DashboardUnits.imperial.badge(.en, app: .miles))
    }

    /// Подвал пикера написан на всех тринадцати и не пуст.
    ///
    /// Сказать, что сохранённые числа не пересчитываются, надо ВСЛУХ: в этом
    /// жанре одни приложения число переименовывают, другие пересчитывают, и
    /// обоим пришлось потом писать предупреждение. Пустой подвал на немецком
    /// телефоне — это то же самое, что не сказать.
    func testTheFootnoteIsWrittenInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            let text = AppStrings.dashboardUnitsPickerFootnote(lang)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(lang.rawValue): подвал пикера пуст")
            // Не подвал «Единиц» приложения: вопросы разные, и один ответ на
            // оба был бы неправдой у одного из них.
            XCTAssertNotEqual(text, AppStrings.unitsPickerFootnote(lang))
        }
    }

    /// Подстановка в подсказке доезжает до текста на всех тринадцати.
    /// Ключ, потерявший `{units}` при переводе, собирается и молча показывает
    /// фразу без единицы — то есть ровно ту строку, ради которой её писали.
    func testTheHintActuallySubstitutesTheUnitName() {
        for lang in LanguageManager.Language.allCases {
            let text = AppStrings.dashboardUnitsFieldHint(lang, units: "ЕДИНИЦА")
            XCTAssertTrue(text.contains("ЕДИНИЦА"),
                          "\(lang.rawValue): подсказка потеряла подстановку — «\(text)»")
            XCTAssertFalse(text.contains("{units}"),
                           "\(lang.rawValue): подстановка осталась неразобранной")
        }
    }

    // MARK: - Выбор не выходит за машину

    /// Экраны машины НЕ ПИШУТ единицу расстояния аккаунта.
    ///
    /// Тот же сторож, что у объёма топлива, и заведён он той же историей: до
    /// 0.6.7 сегмент на карточке конкретной машины писал в глобальную
    /// настройку, и американка, заведённая в российском гараже, переводила в
    /// галлоны весь аккаунт — вместе с сервером и вторым телефоном. Пикер
    /// приборки стоит на том же экране и открывает ту же дверь с другой
    /// стороны: одна «заодно поменяем и в приложении» — и поломка вернулась.
    ///
    /// Запрещена именно ЗАПИСЬ. `DistanceUnit.current` в списке нет намеренно:
    /// форма читает единицу человека в `init` (окружение там ещё не
    /// существует), и читать её она обязана — из неё разрешается `app`.
    func testNoVehicleScreenWritesTheAccountWideDistanceUnit() throws {
        var violations: [String] = []

        for path in Self.vehicleScreens {
            let url = UnitGuard.repoRoot().appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("сторож смотрит в никуда: \(path)")
                continue
            }
            for (index, line) in UnitGuard.strip(text).code.enumerated() {
                for token in Self.accountWideTokens where line.contains(token) {
                    violations.append(
                        "\(path):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty,
                      "экран машины меняет единицу всего аккаунта:\n"
                      + violations.joined(separator: "\n"))
    }

    /// Сторож проверяет сам себя: на подброшенной строке он обязан сработать,
    /// а на законном чтении — промолчать.
    func testTheAccountWideGuardCatchesAPlantedLine() {
        let planted = UnitGuard.strip(
            """
            settings.setDistanceUnit(.miles)
            let units = UnitsManager.shared.distance
            let appDistance = DistanceUnit.current
            settings.setDashboardUnits(vehicleId: id, dashboardUnits)
            """).code

        XCTAssertTrue(Self.accountWideTokens.contains { planted[0].contains($0) },
                      "сторож не видит запись настройки аккаунта")
        XCTAssertTrue(Self.accountWideTokens.contains { planted[1].contains($0) },
                      "сторож не видит писателя настройки аккаунта")
        XCTAssertFalse(Self.accountWideTokens.contains { planted[2].contains($0) },
                       "сторож запретил ЧИТАТЬ единицу человека")
        XCTAssertFalse(Self.accountWideTokens.contains { planted[3].contains($0) },
                       "сторож принял запись помашинной единицы за глобальную")
    }

    /// Экраны, которым настройка аккаунта про расстояние запрещена на запись.
    private static let vehicleScreens = [
        "TripTrack/Views/Garage/VehicleEditFormView.swift",
        "TripTrack/Views/Profile/VehicleDetailView.swift",
        "TripTrack/Views/Garage/GarageView.swift",
        "TripTrack/Models/DashboardUnits.swift"
    ]

    /// Ровно те написания, которыми единица аккаунта пишется: метод
    /// `SettingsManager`, сам её владелец и ключ в `UserDefaults`.
    private static let accountWideTokens = [
        "setDistanceUnit", "UnitsManager", "\"distanceUnit\""
    ]
}
