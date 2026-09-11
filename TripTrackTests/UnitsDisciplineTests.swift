import XCTest
@testable import TripTrack

// MARK: - Чтение исходников

/// Общий инструмент сторожей, которые читают не поведение, а САМ КОД:
/// `UnitsDisciplineTests` (единица у каждого показа) и половина
/// `LocalizationTests` (единица внутри строки перевода).
///
/// Зачем вообще читать исходники тестом. Всё остальное в 0.6.7 проверяет, что
/// сегодняшние сто с лишним мест показа переводят число правильно. Ни один из
/// тех тестов ничего не скажет про место показа, которое напишут завтра: новый
/// экран с «\(km) км» соберётся, пройдёт весь набор и молча покажет километры
/// человеку, выбравшему мили. Поймать это можно только там, где оно и
/// случается — в тексте файла.
enum UnitGuard {

    /// Корень репозитория, выведенный из пути тестового файла: `…/TripTrackTests/X.swift`
    /// → `…`. Аргумент по умолчанию раскрывается У ВЫЗЫВАЮЩЕГО, поэтому любой
    /// тест из этой же папки получит тот же корень, ничего не передавая.
    static func repoRoot(from filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()   // …/TripTrackTests
            .deletingLastPathComponent()   // …
    }

    /// Один прочитанный файл: путь от корня репозитория и две его версии.
    struct SourceFile {
        /// Путь вида `TripTrack/Views/Trips/TripDetailView.swift`.
        let path: String
        /// Строки БЕЗ комментариев, строковые литералы на месте. По ним ищутся
        /// запрещённые токены: единица, объяснённая в комментарии, — это не
        /// показ, а объяснение, и падать на ней значит запретить объяснять.
        let code: [String]
        /// То же, но с выеденным СОДЕРЖИМЫМ литералов (кавычки на месте). По
        /// нему считаются фигурные скобки: `"{"` внутри строки — не блок.
        let skeleton: [String]
    }

    /// Все `.swift` под указанными папками, в порядке пути.
    static func read(dirs: [String], root: URL) -> [SourceFile] {
        let fm = FileManager.default
        var out: [SourceFile] = []
        for dir in dirs {
            let base = root.appendingPathComponent(dir)
            guard let walk = fm.enumerator(atPath: base.path) else { continue }
            var relatives: [String] = []
            for case let item as String in walk where item.hasSuffix(".swift") {
                relatives.append(item)
            }
            for rel in relatives.sorted() {
                let url = base.appendingPathComponent(rel)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let (code, skeleton) = strip(text)
                out.append(SourceFile(path: "\(dir)/\(rel)", code: code, skeleton: skeleton))
            }
        }
        return out
    }

    /// Снимает комментарии, сохраняя нумерацию строк (каждый убранный символ
    /// заменяется пробелом, перевод строки остаётся переводом строки).
    ///
    /// Написано руками, а не регуляркой, из-за одного случая: `"// не комментарий"`
    /// внутри литерала и `"/*"` в строке формата. Регулярка режет их и уносит
    /// с собой полфайла — а это ровно те файлы, где ошибка с единицей и живёт.
    static func strip(_ source: String) -> (code: [String], skeleton: [String]) {
        let s = Array(source)
        var code: [Character] = []
        var skel: [Character] = []
        code.reserveCapacity(s.count)
        skel.reserveCapacity(s.count)

        func keep(_ c: Character, inString: Bool) {
            code.append(c)
            skel.append(inString && c != "\n" ? " " : c)
        }
        func drop(_ c: Character) {
            let blank: Character = c == "\n" ? "\n" : " "
            code.append(blank)
            skel.append(blank)
        }
        func at(_ i: Int, _ c: Character) -> Bool { i < s.count && s[i] == c }

        var i = 0
        while i < s.count {
            // //-комментарий до конца строки
            if s[i] == "/" && at(i + 1, "/") {
                while i < s.count && s[i] != "\n" { drop(s[i]); i += 1 }
                continue
            }
            // /* … */, в Swift они вкладываются
            if s[i] == "/" && at(i + 1, "*") {
                var depth = 0
                while i < s.count {
                    if s[i] == "/" && at(i + 1, "*") {
                        depth += 1; drop(s[i]); drop(s[i + 1]); i += 2; continue
                    }
                    if s[i] == "*" && at(i + 1, "/") {
                        depth -= 1; drop(s[i]); drop(s[i + 1]); i += 2
                        if depth == 0 { break }
                        continue
                    }
                    drop(s[i]); i += 1
                }
                continue
            }
            // raw-строка #"…"#
            if s[i] == "#" && at(i + 1, "\"") {
                keep(s[i], inString: false); keep(s[i + 1], inString: true); i += 2
                while i < s.count {
                    if s[i] == "\"" && at(i + 1, "#") {
                        keep(s[i], inString: true); keep(s[i + 1], inString: false); i += 2; break
                    }
                    keep(s[i], inString: true); i += 1
                }
                continue
            }
            // многострочная """…"""
            if s[i] == "\"" && at(i + 1, "\"") && at(i + 2, "\"") {
                for k in 0..<3 { keep(s[i + k], inString: false) }
                i += 3
                while i < s.count {
                    if s[i] == "\"" && at(i + 1, "\"") && at(i + 2, "\"") {
                        for k in 0..<3 { keep(s[i + k], inString: false) }
                        i += 3; break
                    }
                    keep(s[i], inString: true); i += 1
                }
                continue
            }
            // обычный литерал
            if s[i] == "\"" {
                keep(s[i], inString: false); i += 1
                while i < s.count {
                    if s[i] == "\\" && i + 1 < s.count {
                        keep(s[i], inString: true); keep(s[i + 1], inString: true); i += 2; continue
                    }
                    if s[i] == "\"" { keep(s[i], inString: false); i += 1; break }
                    if s[i] == "\n" { break }   // незакрытый литерал — не глотать весь файл
                    keep(s[i], inString: true); i += 1
                }
                continue
            }
            keep(s[i], inString: false); i += 1
        }
        return (String(code).components(separatedBy: "\n"),
                String(skel).components(separatedBy: "\n"))
    }

    /// Для каждой строки файла — имена функций, внутри которых она стоит.
    ///
    /// Нужно ровно одному файлу, `AppStrings.swift`: он пускается в allowlist
    /// не целиком, а списком функций (почему — см. `unitLabelFunctions`).
    /// «Ближайший `func` выше» здесь не годится: строка ВНЕ функции получила бы
    /// имя предыдущей и молча оказалась прощена.
    static func enclosingFunctions(_ skeleton: [String]) -> [Set<String>] {
        var result: [Set<String>] = []
        var stack: [(name: String, depth: Int)] = []
        var depth = 0
        var pending: String?
        for line in skeleton {
            let before = Set(stack.map(\.name))
            if let declared = declaredFunction(in: line) { pending = declared }
            for ch in line {
                if ch == "{" {
                    if let p = pending { stack.append((p, depth)); pending = nil }
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    while let last = stack.last, last.depth >= depth { stack.removeLast() }
                }
            }
            // Объединение «до» и «после»: строка, на которой функция
            // открывается (`func x() { return "km" }`) или закрывается, тоже
            // принадлежит ей.
            result.append(before.union(stack.map(\.name)))
        }
        return result
    }

    private static func declaredFunction(in line: String) -> String? {
        var search = line.startIndex
        while let r = line.range(of: "func ", range: search..<line.endIndex) {
            let okBefore: Bool = {
                guard r.lowerBound > line.startIndex else { return true }
                let prev = line[line.index(before: r.lowerBound)]
                return !(prev.isLetter || prev.isNumber || prev == "_")
            }()
            if okBefore {
                let name = line[r.upperBound...]
                    .drop(while: { $0 == " " })
                    .prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
                if !name.isEmpty { return String(name) }
            }
            search = r.upperBound
        }
        return nil
    }
}

// MARK: - Сторож

/// Сторож против СЛЕДУЮЩЕЙ версии: он ловит новое место показа, забывшее про
/// единицу.
///
/// Свойство, которое он держит, ровно одно и то же самое, которое
/// `TripDistanceGate` держит для километров: **делит на единицу ровно одно
/// место, и новый экран физически не может напечатать расстояние мимо него.**
///
/// Почему это отдельный тест, а не внимательность на ревью: 0.6.7 перебрала
/// сто пятьдесят семь мест показа за одиннадцать шагов, и ОДНО из них
/// (`mapLockedStats`) уехало мимо `Measure` и нашлось глазами на ревью восьмого
/// шага. Глаза нашли — но глаз в следующей версии может не быть.
///
/// Что сторож НЕ ловит и ловить не умеет: единицу, склеенную с числом внутри
/// готовой строки («212-я миля», «л/100 км»). Такие строки живут в
/// `AppStrings` и в одиннадцати таблицах, и их держит `LocalizationTests` —
/// по ключу и по соседству с числом. Два теста, две половины одной работы.
///
/// Полей у класса нет намеренно: сторожу нечего хранить между тестами, и
/// нечего обнулять в `tearDown`.
final class UnitsDisciplineTests: XCTestCase {

    // MARK: Что запрещено и что звать вместо

    private static let nameAdvice = """
        Хранение и провод метрические и БЕЗЫМЯННЫЕ: `Trip.distance` — метры, \
        `speed` — м/с. Наградам (опыт, уровень машины, значки) — `Trip.scoringKm`, \
        показу — `Measure` с явной единицей.
        """
    private static let factorAdvice = """
        Перевод скорости руками. Делит на единицу только `DistanceUnit`: \
        `speed(fromMetresPerSecond:)` на показ, `metresPerSecond(fromSpeed:)` обратно.
        """
    private static let constantAdvice = """
        Вторая копия константы перевода. Она одна на проект: \
        `DistanceUnit.metresPerMile` (1609.344) и `.metresPerFoot` (0.3048).
        """
    private static let labelAdvice = """
        Подпись километров в обход выбора единицы. Подпись обязана приезжать \
        ВМЕСТЕ с числом: `Measure.distance(metres:unit:lang:)`, \
        `Measure.speed(ms:unit:lang:)`, `Measure.elevation(metres:unit:lang:)` \
        (или их `…Parts`, если число и подпись рисуются разным шрифтом).
        """
    private static let literalAdvice = """
        Единица строкой в коде. Формы подписи собирают \
        `AppStrings.unitDistanceShort/unitSpeedShort/unitElevationShort`, и зовёт \
        их только `Measure` — потому что подпись зависит от ЧИСЛА, а не от языка: \
        «1 миля», «2 мили», «5 миль».
        """

    /// Токены. Список — не догадка: это ровно те написания, которыми 0.6.7
    /// вычищала из проекта старые километры.
    private static let rules: [(token: String, instead: String)] = [
        ("distanceKm", nameAdvice),
        ("speedKmh", nameAdvice),
        ("SpeedKmh", nameAdvice),
        ("* 3.6", factorAdvice),
        ("/ 3.6", factorAdvice),
        ("1609", constantAdvice),
        ("0.3048", constantAdvice),
        ("AppStrings.km(", labelAdvice),
        ("AppStrings.kmh(", labelAdvice),
        ("AppStrings.m(", labelAdvice),
        ("AppStrings.unitMeters(", labelAdvice),
        ("\"km\"", literalAdvice),
        ("\"км\"", literalAdvice),
        ("\" mi\"", literalAdvice),
        ("\"mph\"", literalAdvice)
    ]

    // MARK: Что разрешено и ПОЧЕМУ

    /// Файлы, которым метрическое число — правильный ответ.
    ///
    /// Пара «файл + причина», а не список путей, и это главное в устройстве
    /// сторожа: строка в allowlist обязана быть ВИДИМЫМ РЕШЕНИЕМ в диффе.
    /// Добавленный путь ревьюер пролистает; путь, к которому пришлось написать
    /// причину, — нет. А если причина не пишется, значит места в allowlist и
    /// нет: зови `Measure`.
    ///
    /// Путь — файл или ПАПКА (тогда прощается всё под ней).
    private static let allowlist: [(path: String, reason: String)] = [

        // --- Единственная арифметика -------------------------------------

        ("TripTrackShared/DistanceUnit.swift",
         "Единственная арифметика перевода: 1609.344, 0.3048 и 3.6 живут здесь. "
         + "Сторож для того и написан, чтобы ловить их ВТОРУЮ копию где угодно ещё."),

        // --- Провод на другой процесс: метрический навсегда ---------------

        ("TripTrackShared/TripActivityAttributes.swift",
         "Провод живой активности метрический НАВСЕГДА: `speedKmh`/`distanceKm` везут "
         + "километры, а что нарисовать — говорит отдельное поле `distanceUnit`. "
         + "Переименовать поля нельзя: активность, начатая старым бинарником и "
         + "пережившая обновление, перестанет декодироваться посреди поездки."),

        ("TripTrackShared/LiveActivityFormat.swift",
         "Форматтер за границей процесса: принимает метрический провод и переводит его "
         + "тем же `DistanceUnit`. `Measure` виджету недоступен — он в таргете приложения."),

        ("TripTrackShared/LiveActivityStrings.swift",
         "Подписи за границей таргета: виджет не видит `AppStrings`, и «км»/«mph» для "
         + "него написаны здесь. Что обе стороны границы отвечают побайтово одинаково, "
         + "проверяет `LiveActivityUnitTests`."),

        ("TripTrackLiveActivity/TripTrackLiveActivity.swift",
         "Читает метрический провод (`context.state.distanceKm`) и отдаёт его "
         + "`LiveActivityFormat` вместе с единицей показа."),

        ("TripTrack/Services/LiveActivityManager.swift",
         "Пишет тот же метрический провод; имена параметров повторяют поля `ContentState`, "
         + "иначе их однажды разведут в стороны."),

        ("TripTrack/Services/PhoneConnectivityManager.swift",
         "Словарь `ApplicationContext` для часов: ключи — контракт с другим таргетом. "
         + "Километры в проводе, единица отдельным ключом."),

        ("TripTrack/ViewModels/MapViewModel.swift",
         "Кормит живую активность и часы метрическими числами и пишет лог записи в км/ч. "
         + "Всё, что идёт на ЭКРАН, здесь уже ходит через `Measure`."),

        ("TripTrackWatch/WatchSessionManager.swift",
         "Приёмник того же провода на часах: `speedKmh`/`distanceKm` — имена ключей "
         + "словаря, а не выбор единицы."),

        ("TripTrackWatch/WatchRootView.swift",
         "Единственный экран часов: берёт метрический провод и отдаёт его вместе с "
         + "единицей в `LiveActivityFormat` — тот же форматтер, что у виджета."),

        // --- Награды и пороги: правила игры одинаковы для всех -------------

        ("TripTrack/Models/Trip.swift",
         "`scoringKm` — наградные километры, метрические при любой настройке, плюс "
         + "пороги «стоит/едет» в СИ. Показ у поездки делает `Measure`."),

        ("TripTrack/Models/AutoTripPolicy.swift",
         "Порог мусорной поездки (15 км/ч) — правило записи, человеку не показывается."),

        ("TripTrack/Models/Badge.swift",
         "`BadgeStats.maxSpeedKmh` — вход правил игры. Значок, выданный в милях, был бы "
         + "значком за другую поездку."),

        ("TripTrack/Models/BadgeDefinitions.swift",
         "Пороги значков: 120 км/ч, 42.195 км, 40 075 км. Сравнивает их код — в "
         + "километрах; показывает `BadgeFigure` — через `Measure`."),

        ("TripTrack/Services/BadgeManager.swift",
         "Считает разблокировку по метрическим числам. Опыт и уровень лежат в базе, и "
         + "сдвинуть их конверсией нельзя даже следующим релизом."),

        ("TripTrack/Models/Sync/TripSyncPayload.swift",
         "Порог стоянки (5 км/ч) при разборе трека — та же физика, что у `movementSplit`."),

        ("TripTrack/Models/Vehicle.swift",
         "Расход: пороги 30 и 80 км/ч — характеристика двигателя, а не показ. Литры "
         + "делятся на сотню КИЛОМЕТРОВ, переводит их `ConsumptionUnit` на границе показа."),

        // --- Хранение ------------------------------------------------------

        ("TripTrack/Models/GamificationModels.swift",
         "`RoadEntity.distanceKm` — колонка в базе и редкость дороги по ней. Хранение "
         + "метрическое, как у одометра машины."),

        ("TripTrack/Services/RoadCollectionManager.swift",
         "Пишет и читает ту же колонку."),

        // --- Пороги отрисовки ----------------------------------------------

        ("TripTrack/ViewModels/MyMapViewModel.swift",
         "Градиент трека по скорости: пороги КРАСЯТ линию, а не подписывают число. Для "
         + "миль это была бы перерисовка шкалы (30/60/70), а не деление на 1.609."),

        // --- Слова ----------------------------------------------------------

        ("TripTrack/Localization/Translations",
         "Таблицы переводов. Единственная единица в них — ряд `km`, сама подпись. Слова "
         + "единиц ВНУТРИ строк держит `LocalizationTests`: по ключу и по соседству с "
         + "числом, то есть точнее, чем токен.")
    ]

    /// `AppStrings.swift` пускается не файлом, а СПИСКОМ ФУНКЦИЙ.
    ///
    /// Файлом — значит один раз и навсегда: дальше в него можно дописать что
    /// угодно, и сторож промолчит. Он так уже и промолчал бы про
    /// `mapLockedStats`, которая печатала километры мимо `Measure` весь восьмой
    /// шаг 0.6.7 и нашлась глазами на ревью, а не тестом.
    private static let unitLabelFunctions: [(name: String, reason: String)] = [
        ("km", "сама подпись «км»"),
        ("kmh", "сама подпись «км/ч»"),
        ("unitMeters", "сама подпись «м»"),
        ("unitDistanceShort", "выбирает форму подписи расстояния по числу; зовёт её только `Measure`"),
        ("unitSpeedShort", "то же для скорости"),
        ("unitElevationShort", "то же для высоты"),
        ("unitDistanceBadge", "двухбуквенный значок единицы в пикере: в кружок 32pt не влезает слово")
    ]

    private static let appStringsPath = "TripTrack/Localization/AppStrings.swift"

    /// Папки, которые читает сторож.
    ///
    /// Часы здесь не по спеке, а потому что их таргет НЕ ВХОДИТ в схему сборки
    /// (`project.yml`): их не проверяет даже компилятор, и забытая единица
    /// пролежала бы там до первой пары с реальными часами.
    private static let scannedDirs = [
        "TripTrack", "TripTrackShared", "TripTrackLiveActivity", "TripTrackWatch"
    ]

    // MARK: Собственно проверка

    private struct Violation {
        let path: String
        let line: Int
        let token: String
        let text: String
        let instead: String
    }

    private static let sourceRoot = UnitGuard.repoRoot()

    private static let sourcesExist = FileManager.default.fileExists(
        atPath: sourceRoot.appendingPathComponent("TripTrack").path)

    /// Все нарушения, БЕЗ учёта allowlist — прощение идёт отдельным шагом,
    /// чтобы вторым тестом можно было спросить «а нужна ли ещё эта строка».
    ///
    /// Считается один раз на весь класс: пять мегабайт исходников читаются и
    /// разбираются не настолько быстро, чтобы делать это в каждом тесте.
    private static let rawViolations: [Violation] = sourcesExist ? scanEverything() : []

    private static func scanEverything() -> [Violation] {
        var out: [Violation] = []
        for file in UnitGuard.read(dirs: scannedDirs, root: sourceRoot) {
            let functions = file.path == appStringsPath
                ? UnitGuard.enclosingFunctions(file.skeleton)
                : []
            for (index, line) in file.code.enumerated() {
                if !functions.isEmpty {
                    let here = functions[index]
                    if unitLabelFunctions.contains(where: { here.contains($0.name) }) { continue }
                }
                for rule in rules where line.contains(rule.token) {
                    out.append(Violation(path: file.path, line: index + 1, token: rule.token,
                                         text: line.trimmingCharacters(in: .whitespaces),
                                         instead: rule.instead))
                }
            }
        }
        return out
    }

    private static func allowed(_ path: String) -> Bool {
        allowlist.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    /// Без исходников сторожу нечего читать. Пропуск, а не падение: прогон на
    /// машине без чекаута покраснел бы на пустом месте, и первое, что сделали
    /// бы с таким тестом, — выключили.
    private func requireSources() throws {
        guard Self.sourcesExist else {
            throw XCTSkip(
                "Исходников рядом с тестом нет (\(Self.sourceRoot.path)) — сторожу нечего читать")
        }
    }

    /// Главный тест версии: ни одно место показа не печатает расстояние,
    /// скорость или высоту мимо `Measure`.
    func testNoOnePrintsDistanceBehindMeasure() throws {
        try requireSources()
        let found = Self.rawViolations.filter { !Self.allowed($0.path) }

        for violation in found.prefix(25) {
            XCTFail("""

                \(violation.path):\(violation.line) — «\(violation.token)» мимо единицы.
                  строка:  \(violation.text.prefix(160))
                  звать:   \(violation.instead)
                  если число тут метрическое ПО ДЕЛУ (провод, награда, порог, хранение) — \
                впиши файл в `allowlist` в `UnitsDisciplineTests` ВМЕСТЕ С ПРИЧИНОЙ.
                """)
        }
        XCTAssertTrue(found.isEmpty,
                      "Мест показа мимо `Measure`: \(found.count) в \(Set(found.map(\.path)).count) файлах")
    }

    /// Allowlist не имеет права заплывать жиром.
    ///
    /// Файл однажды почистят — и строка останется, а вместе с ней останется
    /// дыра ровно там, где её никто не ищет. Этот тест падает на УЛУЧШЕНИИ
    /// кода, и это правильная цена: удалить строку — пять секунд, найти
    /// забытое прощение через год — нельзя.
    func testEveryAllowlistLineIsStillNeeded() throws {
        try requireSources()
        let violating = Set(Self.rawViolations.map(\.path))

        for entry in Self.allowlist {
            let used = violating.contains {
                $0 == entry.path || $0.hasPrefix(entry.path + "/")
            }
            XCTAssertTrue(used, """

                `\(entry.path)` больше не нарушает ни одного правила единиц — \
                удали строку из `allowlist` в `UnitsDisciplineTests`.
                  причина, которая там записана: \(entry.reason)
                """)
        }
    }

    /// Функции подписей — это СПИСОК, и он тоже не должен протухать.
    func testUnitLabelFunctionsStillExistAndStillNeedTheException() throws {
        try requireSources()
        let url = Self.sourceRoot.appendingPathComponent(Self.appStringsPath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let (code, skeleton) = UnitGuard.strip(text)
        let functions = UnitGuard.enclosingFunctions(skeleton)

        for entry in Self.unitLabelFunctions {
            let lines = (0..<code.count).filter { functions[$0].contains(entry.name) }
            XCTAssertFalse(lines.isEmpty, """
                `AppStrings.\(entry.name)` больше нет — убери её из `unitLabelFunctions`.
                  причина, которая там записана: \(entry.reason)
                """)
        }
    }

    // MARK: Сам сторож под сторожем

    /// Тест, который проверяет ТЕСТ: на подброшенной строке он обязан сработать.
    ///
    /// Без этого сторож — самый опасный вид зелёного: он читает файлы, ничего
    /// не находит и выглядит работающим, даже если в нём перепутаны папки или
    /// комментарии съели весь код.
    func testTheGuardActuallyCatchesAPlantedLine() {
        let planted = """
            struct NewScreen: View {
                var body: some View {
                    let distanceKm = trip.distance / 1000
                    Text("\\(distanceKm) \\(AppStrings.km(lang))")
                    Text("\\(trip.averageSpeed * 3.6) km/h")
                    Text(miles ? "mph" : "km")
                }
            }
            """
        let (code, _) = UnitGuard.strip(planted)
        var caught: Set<String> = []
        for line in code {
            for rule in Self.rules where line.contains(rule.token) { caught.insert(rule.token) }
        }
        // Четыре разных способа забыть про единицу — и каждый ловится своим
        // правилом, а не одним общим «что-то тут про километры».
        XCTAssertTrue(caught.contains("distanceKm"), "не увидел имя с единицей")
        XCTAssertTrue(caught.contains("* 3.6"), "не увидел перевод скорости руками")
        XCTAssertTrue(caught.contains("AppStrings.km("), "не увидел подпись мимо `Measure`")
        XCTAssertTrue(caught.contains("\"mph\""), "не увидел единицу строкой")
    }

    /// Комментарии не считаются: единица, ОБЪЯСНЁННАЯ словами, — это документ,
    /// а не показ. Иначе первым, что сделает следующий разработчик, будет
    /// удаление объяснений, чтобы тест позеленел.
    func testCommentsAreNotAViolation() {
        let source = """
            // Считает километры: distance / 1000, потом * 3.6 для км/ч.
            /* «км» и "mph" здесь тоже просто слова */
            let shown = Measure.distance(metres: trip.distance, unit: unit, lang: lang)
            """
        let (code, _) = UnitGuard.strip(source)
        for line in code {
            for rule in Self.rules {
                XCTAssertFalse(line.contains(rule.token),
                               "комментарий принят за нарушение: «\(rule.token)» в «\(line)»")
            }
        }
        XCTAssertTrue(code.joined().contains("Measure.distance"), "снос комментариев съел код")
    }

    /// А литерал, в котором стоит `//`, комментарием не считается — иначе
    /// стриппер проглотил бы хвост файла вместе с настоящим нарушением.
    func testASlashInsideALiteralDoesNotEatTheLine() {
        let source = "let url = \"https://trip-track.app\" ; let bad = \"km\""
        let (code, _) = UnitGuard.strip(source)
        XCTAssertTrue(code.joined().contains("\"km\""),
                      "литерал с // проглотил строку: \(code.joined())")
    }
}
