import XCTest
@testable import TripTrack

/// Единица приборки НЕ доходит до наград — и до любой суммы по нескольким
/// машинам.
///
/// Сосед `ScoringStaysMetricTests` сторожит единицу ЧЕЛОВЕКА: выбрал мили —
/// опыт и значки не сдвинулись. Здесь второй вход в ту же комнату, открытый
/// версией 0.6.7: единица МАШИНЫ. Она опаснее ровно тем, что её у каждой
/// машины своя, а `Vehicle` лежит под рукой у всего, что считает километры, —
/// достаточно одного `vehicle.dashboardUnit(app:)`, вписанного «чтобы
/// показывало как на панели», и уровень машины уедет на 1.609 у половины
/// гаража. Опыт и уровень лежат В БАЗЕ: это единственная поломка версии,
/// которую не чинит следующий релиз — откатывать нечего, цифры уже переписаны.
///
/// Половина теста читает САМ КОД, и это не паранойя, а единственный способ
/// поймать место, которого сегодня ещё нет. Поведенческая половина скажет, что
/// сегодняшние награды считаются правильно; про награду, которую напишут в
/// 0.6.8, она не скажет ничего.
///
/// Второе правило здесь же и по той же причине: **ни одна функция, куда
/// приходит больше одной машины, не имеет права читать единицу машины.** У
/// суммы миль и километров единицы не существует, а правило «взять у первой»
/// человек не угадает никогда — именно на этом aCar получил жалобы «смесь KM и
/// Miles». Поэтому сводки стоят в списке рядом с наградами.
final class VehicleUnitsStayOutOfRewardsTests: XCTestCase {

    /// Файлы, которым единица машины запрещена, и ПОЧЕМУ каждому.
    ///
    /// Пара «файл + причина», а не список путей: строка без причины — это
    /// строка, которую ревьюер пролистает. Если причина не пишется, значит
    /// файлу здесь не место.
    private static let forbidden: [(path: String, reason: String)] = [
        ("TripTrack/Models/Trip.swift",
         "`scoringKm` — наградные километры поездки. Поездка вообще не обязана знать, "
         + "что у машины на панели: значок, выданный по милям, был бы значком за другую дорогу."),

        ("TripTrack/Models/Badge.swift",
         "`BadgeStats` — вход правил игры."),

        ("TripTrack/Models/BadgeDefinitions.swift",
         "Пороги значков. Правила игры одинаковы для всех, а не для каждой машины свои."),

        ("TripTrack/Models/GamificationModels.swift",
         "`VehicleLevelSystem` — лестница уровней машины. Уровень лежит в базе, "
         + "и сдвинутый конверсией он не чинится следующим релизом."),

        ("TripTrack/Services/GamificationManager.swift",
         "Считает опыт и уровень. Оба в базе."),

        ("TripTrack/Services/BadgeManager.swift",
         "Выдаёт значки по метрическим числам."),

        ("TripTrack/Services/VehicleOdometer.swift",
         "Треканный пробег машины — НАГРАДНОЕ число (от него уровень). Считается в метрах, "
         + "делится один раз в конце, и приборка в этом не участвует."),

        ("TripTrack/Models/TripDistanceGate.swift",
         "Единственное место, где набираются километры поездки. Единица показа сюда не ходит."),

        ("TripTrack/Models/TripLevelHistory.swift",
         "Исторический уровень на карточке — тот же уровень, тот же запрет."),

        ("TripTrack/Models/JourneyAggregate.swift",
         "Итоги путешествия складывают ПЛЕЧИ, а плечи бывают на разных машинах: "
         + "у суммы миль и километров единицы не существует."),

        ("TripTrack/Services/StatsCache.swift",
         "Сводка по всем поездкам — единица приложения по построению."),

        ("TripTrack/Views/Profile/StatsScreenView.swift",
         "«Статистика» и Wrapped: сквозные по построению, машин там много, единица одна — человека.")
    ]

    private static let tokens = ["dashboardUnit", "DashboardUnits"]

    /// Читает те же исходники и тем же инструментом, что `UnitsDisciplineTests`:
    /// комментарии сняты, литералы на месте. Единица, ОБЪЯСНЁННАЯ словами, —
    /// это документ, а не показ, и падать на ней значит запретить объяснять.
    func testNoRewardOrSummaryFileEverAsksAVehicleForItsUnit() throws {
        let root = UnitGuard.repoRoot()
        var missing: [String] = []
        var violations: [String] = []

        for entry in Self.forbidden {
            let url = root.appendingPathComponent(entry.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                missing.append(entry.path)
                continue
            }
            let code = UnitGuard.strip(text).code
            for (index, line) in code.enumerated() {
                guard Self.tokens.contains(where: { line.contains($0) }) else { continue }
                violations.append("""
                \(entry.path):\(index + 1)
                    \(line.trimmingCharacters(in: .whitespaces))
                    ПОЧЕМУ НЕЛЬЗЯ: \(entry.reason)
                """)
            }
        }

        // Файл переименовали или удалили — сторож обязан сказать об этом, а не
        // позеленеть на пустом месте. Молчащий сторож хуже отсутствующего.
        XCTAssertTrue(missing.isEmpty,
                      "сторож смотрит в никуда:\n" + missing.joined(separator: "\n"))
        XCTAssertTrue(violations.isEmpty,
                      "единица приборки дошла до награды или до сводки:\n\n"
                      + violations.joined(separator: "\n\n"))
    }

    /// Сторож проверяет сам себя: на подброшенной строке он обязан сработать.
    /// Без этого он самый опасный вид зелёного — читает файлы, ничего не
    /// находит и выглядит работающим.
    func testTheGuardCatchesAPlantedLine() {
        let planted = UnitGuard.strip(
            "let u = vehicle.dashboardUnit(app: .km)\n// dashboardUnit в комментарии\n").code
        XCTAssertTrue(planted[0].contains("dashboardUnit"), "сторож не видит настоящую строку")
        XCTAssertFalse(planted[1].contains("dashboardUnit"), "сторож считает комментарий нарушением")
    }

    // MARK: - Поведение: цифры не двигаются

    /// Уровень подставляется посчитанным, а не единицей из умолчания: иначе
    /// «прогресс до следующего» считался бы от первой ступени и совпал бы у
    /// всех трёх машин просто потому, что считать было нечего.
    private func car(_ units: DashboardUnits) -> Vehicle {
        Vehicle(name: "Тойота", odometerKm: 100_000, manualOdometerKm: 142_000,
                level: VehicleLevelSystem.level(for: 100_000),
                dashboardUnits: units)
    }

    /// Уровень, прогресс и «до следующего» — от одного и того же числа при
    /// любой приборке. Побитово: это не про «примерно те же», это про
    /// хранилище.
    func testLevelAndProgressDoNotMoveWithTheDashboardUnit() {
        let metric = car(.metric)
        let imperial = car(.imperial)
        let asApp = car(.app)

        XCTAssertEqual(metric.level, imperial.level)
        XCTAssertEqual(metric.level, asApp.level)
        XCTAssertEqual(metric.progressToNextLevel, imperial.progressToNextLevel)
        XCTAssertEqual(metric.kmToNextLevel, imperial.kmToNextLevel)
        XCTAssertEqual(metric.levelSourceKm, imperial.levelSourceKm)
    }

    /// И считается уровень от ТРЕКАННОГО пробега, а не от того, что списали с
    /// панели. Соблазн зачесть ручной («он же настоящий») — вторая тропа к той
    /// же беде: тогда единица машины стала бы входом награды, и уровни начали
    /// бы раздаваться за цифру с клавиатуры.
    func testTheLevelIsCountedFromWhatTheAppSawItself() {
        let v = car(.imperial)

        XCTAssertEqual(v.levelSourceKm, v.odometerKm)
        XCTAssertNotEqual(v.levelSourceKm, v.manualOdometerKm)
        // Числа подобраны так, что подмена была бы ВИДНА: треканный и ручной
        // стоят на разных ступенях лестницы.
        XCTAssertNotEqual(VehicleLevelSystem.level(for: 100_000),
                          VehicleLevelSystem.level(for: 142_000))
        XCTAssertEqual(VehicleLevelSystem.level(for: v.levelSourceKm),
                       VehicleLevelSystem.level(for: v.odometerKm))
    }

    /// Треканный пробег машины складывается из метров поездок и про приборку
    /// не спрашивает — спросить ему нечего, машина туда не приходит вовсе.
    func testTrackedOdometerIsBuiltFromMetresAndKnowsNothingAboutDashboards() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trips = [
            Trip(startDate: start, endDate: start.addingTimeInterval(3600),
                 distance: 50_000, vehicleId: id),
            Trip(startDate: start, endDate: start.addingTimeInterval(7200),
                 distance: 70_000, vehicleId: id)
        ]

        XCTAssertEqual(VehicleOdometer.tracked(from: trips, vehicleId: id), 120,
                       accuracy: 0.000_001)
    }
}
