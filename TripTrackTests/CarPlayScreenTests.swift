import XCTest
@testable import TripTrack

/// Экран автомобиля проверяется ЗДЕСЬ, а не в CarPlay.
///
/// Шаблоны `CPInformationTemplate` живут только внутри подключённой сцены, и
/// увидеть их можно ровно одним способом — симулятором CarPlay, глазами. Но
/// вопрос, на который экран отвечает, значение: какие строки и какие кнопки
/// человек видит в каждом состоянии записи. Поэтому решение вынесено чистой
/// функцией (`CarPlayScreen.model`), а сборка шаблона осталась тонким слоем
/// над ней — тот же приём, что у `ProPaywallPhase` и `AtlasSlot`.
final class CarPlayScreenTests: XCTestCase {

    private let langs = LanguageManager.Language.allCases

    // MARK: - Кнопки

    /// Состав кнопок задан ПОЛНОСТЬЮ и по состояниям.
    ///
    /// Буквально списками, а не «есть ли среди них пауза»: лишняя кнопка за
    /// рулём — это промах пальцем по соседней, и поймать её можно только
    /// сравнением всего набора.
    func testEachStateOffersExactlyItsOwnButtons() {
        XCTAssertEqual(
            CarPlayScreen.model(.recording(metres: 1_000, duration: "10:00", speedMetresPerSecond: 20),
                                unit: .km, lang: .ru).actions,
            [.pause, .finish])

        XCTAssertEqual(
            CarPlayScreen.model(.paused(metres: 1_000, duration: "10:00"),
                                unit: .km, lang: .ru).actions,
            [.resume, .finish])

        XCTAssertEqual(
            CarPlayScreen.model(.idle, unit: .km, lang: .ru).actions,
            [.start])
    }

    /// У недоступного экрана кнопок НЕТ ВОВСЕ.
    ///
    /// Это правило приложения, а не мелочь: `MapViewModel` живёт в
    /// `ContentView`, и пока экран телефона ни разу не собрался, командовать
    /// записью нечем. Кнопка «Начать», которая ничего не сделает, хуже
    /// отсутствующей — и за рулём особенно, потому что второй раз человек
    /// нажмёт её уже на ходу.
    func testUnavailableOffersNothingToPress() {
        let m = CarPlayScreen.model(.unavailable, unit: .km, lang: .ru)
        XCTAssertTrue(m.actions.isEmpty)
        XCTAssertFalse(m.items.isEmpty, "объяснить, почему пусто, всё равно надо")
    }

    // MARK: - Строки

    /// На паузе скорости НЕТ.
    ///
    /// Она ноль по определению, и показать её значило бы выдать ноль за факт
    /// о дороге. Проверяется числом строк, а не отсутствием подстроки:
    /// «0 км/ч» на тринадцати языках пишется по-разному.
    func testPausedHidesSpeedInsteadOfShowingZero() {
        let paused = CarPlayScreen.model(.paused(metres: 42_195, duration: "1:02:03"),
                                         unit: .km, lang: .ru)
        XCTAssertEqual(paused.items.count, 2)

        let recording = CarPlayScreen.model(
            .recording(metres: 42_195, duration: "1:02:03", speedMetresPerSecond: 0),
            unit: .km, lang: .ru)
        XCTAssertEqual(recording.items.count, 3, "на записи скорость есть, даже нулевая")
    }

    /// Порядок строк записи фиксирован: расстояние, время, скорость.
    ///
    /// За рулём взгляд достаётся первой строке, и какая из трёх ею будет —
    /// решение, а не побочный результат сборки.
    func testRecordingRowsKeepTheirOrder() {
        let m = CarPlayScreen.model(
            .recording(metres: 1_000, duration: "10:00", speedMetresPerSecond: 20),
            unit: .km, lang: .ru)
        XCTAssertEqual(m.items.map(\.title),
                       [AppStrings.carPlayDistance(.ru),
                        AppStrings.carPlayTime(.ru),
                        AppStrings.carPlaySpeed(.ru)])
    }

    /// «Ничего не пишется» и «нечем командовать» — РАЗНЫЕ ответы.
    ///
    /// Оба состояния выглядят одинаково пустыми, и слить их в одну фразу
    /// легко; но человеку, у которого приложение не запускалось, «нет
    /// активной поездки» не говорит, что делать.
    func testIdleAndUnavailableSayDifferentThings() {
        for l in langs {
            let idle = CarPlayScreen.model(.idle, unit: .km, lang: l).items[0].title
            let dead = CarPlayScreen.model(.unavailable, unit: .km, lang: l).items[0].title
            XCTAssertNotEqual(idle, dead, "\(l.rawValue): одна фраза на два разных случая")
        }
    }

    /// Ни одной пустой строки ни на одном из тринадцати языков.
    ///
    /// Забытый ключ падает на английский молча (см. `LocalizationTests`), а
    /// вот пустое значение в таблице дало бы на экране автомобиля строку без
    /// подписи — и заметить это можно было бы только сев в машину.
    func testNothingIsEmptyInAnyLanguage() {
        let states: [CarPlayScreen.State] = [
            .recording(metres: 1_000, duration: "10:00", speedMetresPerSecond: 20),
            .paused(metres: 1_000, duration: "10:00"),
            .idle,
            .unavailable,
        ]
        for l in langs {
            for u in DistanceUnit.allCases {
                for s in states {
                    let m = CarPlayScreen.model(s, unit: u, lang: l)
                    XCTAssertFalse(m.title.isEmpty, "\(l.rawValue)/\(u.rawValue): пустой заголовок")
                    for i in m.items {
                        XCTAssertFalse(i.title.isEmpty, "\(l.rawValue)/\(u.rawValue): пустая строка")
                        XCTAssertNotEqual(i.detail, "", "\(l.rawValue)/\(u.rawValue): пустое значение")
                    }
                    for a in m.actions {
                        XCTAssertFalse(CarPlayScreen.title(a, lang: l).isEmpty,
                                       "\(l.rawValue): кнопка \(a) без подписи")
                    }
                }
            }
        }
    }

    /// Подписи кнопок КОРОТКИЕ на всех тринадцати языках.
    ///
    /// Бюджет здесь — на ТЕКСТ, а не на отрисовку, и сказано это прямо:
    /// шрифт и ширину кнопки задаёт сама машина, они разные у разных
    /// автомобилей, и честно измерить их нечем. Зато обрезанную подпись видно
    /// ровно в одном месте — за рулём, — и поймать её надо раньше.
    ///
    /// Четырнадцать — не круглое число с потолка: «Начать запись» выходило
    /// двадцать знаков по-немецки и двадцать пять по-французски, а самая
    /// длинная из оставшихся подписей («Ipagpatuloy») — одиннадцать. Порог
    /// стоит между ними. Не влезает новая подпись — сокращай подпись, а не
    /// порог: объект действия на этом экране всегда ясен из заголовка.
    func testButtonTitlesStayShortEnoughForACarScreen() {
        let budget = 14
        let actions: [CarPlayScreen.Action] = [.start, .pause, .resume, .finish]
        for l in langs {
            for a in actions {
                let title = CarPlayScreen.title(a, lang: l)
                XCTAssertLessThanOrEqual(
                    title.count, budget,
                    "\(l.rawValue)/\(a): «\(title)» — \(title.count) знаков, "
                    + "на кнопке в машине это обрежется")
            }
        }
    }

    /// «Пауза» и «Продолжить» не совпадают ни на одном языке.
    ///
    /// Они занимают одно и то же место на экране в противоположных
    /// состояниях: совпади подписи — и человек не отличит остановленную
    /// запись от идущей, не отводя глаз от дороги.
    func testPauseAndResumeNeverReadTheSame() {
        for l in langs {
            XCTAssertNotEqual(CarPlayScreen.title(.pause, lang: l),
                              CarPlayScreen.title(.resume, lang: l),
                              "\(l.rawValue): пауза и продолжение подписаны одинаково")
        }
    }

    // MARK: - Единицы

    /// Единица ДОЕЗЖАЕТ до экрана автомобиля.
    ///
    /// CarPlay — новое место показа расстояния (правило 0.6.7), и вопрос
    /// здесь ровно один: считает ли оно мили тому, кто выбрал мили. Проверка
    /// «строка равна `Measure.distance(...)`» была бы тавтологией — модель её
    /// и зовёт; а вот «в милях и в километрах написано РАЗНОЕ» ловит и
    /// прибитую единицу, и потерянный параметр.
    func testDistanceAndSpeedFollowThePersonsUnit() {
        let state = CarPlayScreen.State.recording(
            metres: 100_000, duration: "1:30:00", speedMetresPerSecond: 25)
        let metric = CarPlayScreen.model(state, unit: .km, lang: .en)
        let imperial = CarPlayScreen.model(state, unit: .miles, lang: .en)

        XCTAssertNotEqual(metric.items[0].detail, imperial.items[0].detail, "100 км ≠ 62 mi")
        XCTAssertNotEqual(metric.items[2].detail, imperial.items[2].detail, "90 км/ч ≠ 56 mph")
    }

    /// Расстояние печатает `Measure`, и только он.
    ///
    /// Здесь это проверяется равенством нарочно: единственное место деления
    /// на единицу — `DistanceUnit`, единственное место печати — `Measure`
    /// (правило 0.6.7), и если однажды экран автомобиля начнёт собирать
    /// строку сам, разойдётся он молча.
    func testStringsComeFromMeasure() {
        let m = CarPlayScreen.model(
            .recording(metres: 42_195, duration: "3:41:00", speedMetresPerSecond: 3.2),
            unit: .miles, lang: .de)
        XCTAssertEqual(m.items[0].detail,
                       Measure.distance(metres: 42_195, unit: .miles, lang: .de))
        XCTAssertEqual(m.items[2].detail,
                       Measure.speed(ms: 3.2, unit: .miles, lang: .de))
    }

    // MARK: - Тонкий слой

    /// Обновление экрана пишет КАЖДОЕ поле модели.
    ///
    /// Сам `CarPlayController` тестом не задать — шаблоны живут только внутри
    /// подключённой сцены. А задать можно вот что: у `Model` три поля, и все
    /// три обязаны переписываться на обновлении. Забытым был `title` — экран
    /// автомобиля показывал «Записывается» над остановленной записью, то есть
    /// врал о единственном, что человеку за рулём от него нужно. Поймано
    /// сверкой с заголовками SDK, не сборкой.
    ///
    /// Состав полей берётся `Mirror`'ом с живой модели, а не разбором текста:
    /// добавит кто-то четвёртое поле — сторож спросит про него сам, без
    /// правки этого теста. Тот же приём чтения исходников, что у
    /// `UnitsDisciplineTests`.
    func testRefreshWritesEveryFieldOfTheModel() throws {
        let sample = CarPlayScreen.model(.idle, unit: .km, lang: .en)
        let fields = Mirror(reflecting: sample).children.compactMap { $0.label }
        XCTAssertEqual(Set(fields), ["title", "items", "actions"],
                       "состав модели изменился — проверь, что обновление знает про новое поле")

        // Корень репозитория — общим `UnitGuard.repoRoot()`, а не своей
        // арифметикой пути: аргумент по умолчанию раскрывается у вызывающего,
        // и второй копии этой логики быть не должно.
        let url = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/CarPlay/CarPlayController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        for field in fields {
            XCTAssertTrue(source.contains("template.\(field) ="),
                          "CarPlayController не переписывает template.\(field) — "
                          + "экран автомобиля покажет прошлое значение")
        }
    }

    /// Время приходит готовым и НЕ переписывается.
    ///
    /// `MapViewModel.duration` — уже собранная строка, та же, что на экране
    /// телефона и в Live Activity. Собрать её здесь второй раз значило бы
    /// однажды показать в машине не то время, что на телефоне.
    func testDurationIsPassedThroughUntouched() {
        let m = CarPlayScreen.model(
            .recording(metres: 1_000, duration: "7:07:07", speedMetresPerSecond: 1),
            unit: .km, lang: .tr)
        XCTAssertEqual(m.items[1].detail, "7:07:07")
    }
}
