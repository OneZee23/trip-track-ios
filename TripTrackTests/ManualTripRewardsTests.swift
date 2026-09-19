import XCTest
@testable import TripTrack

/// Вписанная рукой поездка не приносит наград — и это сторожит САМ КОД.
///
/// Сосед `VehicleUnitsStayOutOfRewardsTests` объясняет приём словами:
/// поведенческая половина скажет, что сегодняшние награды считаются правильно;
/// про награду, которую напишут в 0.8.1, она не скажет ничего. Здесь ровно тот
/// же случай, только с более дорогой ценой ошибки: опыт, уровень и значки
/// лежат В БАЗЕ, и опыт, начисленный за нарисованный по карте маршрут, не
/// откатывается следующим релизом — откатывать нечего, цифры уже переписаны.
///
/// Вторая половина теста — про то, что гейт НЕ расползся: километры вписанной
/// поездки настоящие, и слой открытого, места и одометр обязаны их считать.
/// Сторож, который запретил бы и это, был бы хуже отсутствующего.
@MainActor
final class ManualTripRewardsTests: XCTestCase {

    /// Хранилище — ОДНО на класс, и живёт оно до конца прогона. Заведи его по
    /// штуке на тест — и фоновая работа CoreData, начатая внутри, дописывала
    /// бы в контекст умершего хранилища: куча портится молча, а падает от
    /// этого ЧУЖОЙ класс (CLAUDE.md, «Ловушки»). См. тот же приём в
    /// `ManualTripFlowTests`.
    private static let pc = PersistenceController(inMemory: true)

    /// Наградные места и ПОЧЕМУ каждому нужен гейт.
    ///
    /// Пара «файл + причина», а не список путей: строка без причины — это
    /// строка, которую ревьюер пролистает.
    private static let guarded: [(path: String, reason: String)] = [
        ("TripTrack/Services/GamificationManager.swift",
         "Опыт и уровень профиля. Оба в базе, и оба считаются от `scoringKm` — "
         + "числа, которое у вписанной поездки взялось из линии MKDirections."),

        ("TripTrack/Services/BadgeManager.swift",
         "Значки и рекорд скорости. У вписанной поездки «максимум» это средняя, "
         + "назначенная человеком, — значок за 120 км/ч выдавался бы за набранное число."),

        ("TripTrack/Services/Discoveries/DiscoveryProcessor.swift",
         "Секреты, загадки и вехи. Зачёт только по ЗАПИСАННОМУ треку (0.7.0): "
         + "печать за тап по карте обесценивает все остальные.")
    ]

    /// То, что километры вписанной поездки засчитывает.
    private static let unfiltered: [(path: String, reason: String)] = [
        ("TripTrack/Services/Reveal/RevealedLayerStore.swift",
         "Слой открытого. Дорога, по которой человек проехал, открыта — независимо "
         + "от того, записал он её треком или вписал потом (спека §2: атлас — ДА)."),

        ("TripTrack/Services/VehicleOdometer.swift",
         "Треканный пробег машины. Спека §2 засчитывает вписанные километры в одометр.")
    ]

    // MARK: - Гейт стоит

    func testEveryRewardFileCarriesTheSourceGuard() throws {
        let root = UnitGuard.repoRoot()
        var missing: [String] = []
        var ungated: [String] = []

        for entry in Self.guarded {
            let url = root.appendingPathComponent(entry.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                missing.append(entry.path)
                continue
            }
            // Комментарии сняты: гейт, ОПИСАННЫЙ словами, — это документ, а не
            // проверка. Тот же инструмент, что у `UnitsDisciplineTests`.
            let code = UnitGuard.strip(text).code
            let hasGuard = code.contains { line in
                line.contains("source == .recorded") || line.contains(".source == .recorded")
            }
            if !hasGuard { ungated.append("\(entry.path)\n    ПОЧЕМУ НУЖЕН: \(entry.reason)") }
        }

        XCTAssertTrue(missing.isEmpty,
                      "сторож смотрит в никуда:\n" + missing.joined(separator: "\n"))
        XCTAssertTrue(ungated.isEmpty,
                      "наградное место без гейта по `Trip.source`:\n\n"
                      + ungated.joined(separator: "\n\n"))
    }

    // MARK: - И не расползся

    func testTheAtlasAndTheOdometerDoNotFilterBySource() throws {
        let root = UnitGuard.repoRoot()
        var missing: [String] = []
        var overreach: [String] = []

        for entry in Self.unfiltered {
            let url = root.appendingPathComponent(entry.path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                missing.append(entry.path)
                continue
            }
            let code = UnitGuard.strip(text).code
            for (index, line) in code.enumerated() where line.contains("source == .recorded") {
                overreach.append("""
                \(entry.path):\(index + 1)
                    \(line.trimmingCharacters(in: .whitespaces))
                    ПОЧЕМУ НЕЛЬЗЯ: \(entry.reason)
                """)
            }
        }

        XCTAssertTrue(missing.isEmpty,
                      "сторож смотрит в никуда:\n" + missing.joined(separator: "\n"))
        XCTAssertTrue(overreach.isEmpty,
                      "гейт наград дошёл туда, где километры засчитываются:\n\n"
                      + overreach.joined(separator: "\n\n"))
    }

    /// Сторож проверяет сам себя: на подброшенной строке он обязан сработать,
    /// а на комментарии — нет. Без этого он самый опасный вид зелёного.
    func testTheGuardCatchesAPlantedLine() {
        let planted = UnitGuard.strip(
            "guard trip.source == .recorded else { return }\n"
            + "// source == .recorded в комментарии\n").code
        XCTAssertTrue(planted[0].contains("source == .recorded"), "сторож не видит настоящую строку")
        XCTAssertFalse(planted[1].contains("source == .recorded"),
                       "сторож считает комментарий проверкой")
    }

    // MARK: - Поведение: цифры не двигаются

    private func manual(km: Double) -> Trip {
        var trip = Trip(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            distance: km * 1000,
            maxSpeed: 40,
            averageSpeed: 40,
            source: .manual
        )
        trip.region = "Краснодарский край"
        return trip
    }

    private func recorded(km: Double) -> Trip {
        var trip = manual(km: km)
        trip.source = .recorded
        return trip
    }

    func testManualTripEarnsNoXP() {
        let suite = "manual-trip-rewards-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GamificationManager(persistenceController: Self.pc, defaults: defaults)
        let hand = manual(km: 300)
        let driven = recorded(km: 300)

        XCTAssertEqual(manager.calculateXP(for: hand, allTrips: [hand]).total, 0)
        XCTAssertGreaterThan(manager.calculateXP(for: driven, allTrips: [driven]).total, 0)
    }

    func testManualTripDoesNotMoveBadgeStats() {
        let hand = manual(km: 600)
        let driven = recorded(km: 600)

        let handStats = BadgeManager.computeStats(from: [hand])
        XCTAssertEqual(handStats.totalDistanceKm, 0)
        XCTAssertEqual(handStats.maxSpeedKmh, 0)

        let drivenStats = BadgeManager.computeStats(from: [driven])
        XCTAssertGreaterThan(drivenStats.totalDistanceKm, 0)
        XCTAssertGreaterThan(drivenStats.maxSpeedKmh, 0)
    }

    /// Одометр — другая сторона правила: вписанные километры машина проехала.
    func testManualTripStillCountsTowardTheVehicleOdometer() {
        let vehicleId = UUID()
        var hand = manual(km: 120)
        hand.vehicleId = vehicleId

        let tracked = VehicleOdometer.trackedByVehicle(from: [hand])
        XCTAssertEqual(tracked[vehicleId] ?? 0, 120, accuracy: 0.001)
    }
}
