import Foundation

/// Что поездка открыла — одним ответом экрану итогов.
///
/// Собирается ПОСЛЕ финиша и ровно один раз: `DiscoveryProcessor` кладёт сюда
/// только НОВОЕ (то, чего в базе не было), поэтому второй разбор той же поездки
/// даёт пустую сводку, а не радостный список из того же самого. Километры и
/// регионы приходят из `RevealedLayerStore.IngestDelta` — их считает туман, и
/// второго счёта здесь нет.
///
/// `Codable` не ради сети (находки живут только на телефоне до волны 3), а ради
/// цены ошибки: сводка ездит в `TripCompletionData`, и однажды её захотят
/// пережить перезапуск между «значки» и «итоги».
struct TripDiscoveries: Equatable, Codable {
    let tripId: UUID
    /// Новых километров открытого мира — из дельты тумана.
    let newKm: Double
    /// Регионы, увиденные впервые (ISO 3166-2) — оттуда же.
    let newRegionIds: [String]
    let secrets: [Discovery]
    let riddles: [Discovery]
    let milestones: [Discovery]

    /// Полкилометра — порог «поездка и правда что-то открыла»: шум GPS на
    /// стоянке открывает ячейку-другую, и строка «открыто 0.1 км» читалась бы
    /// как насмешка.
    var isEmpty: Bool {
        newKm < 0.5 && newRegionIds.isEmpty && secrets.isEmpty && riddles.isEmpty && milestones.isEmpty
    }

    var count: Int { secrets.count + riddles.count + milestones.count }

    /// Все находки одним списком, в том порядке, в каком их показывает экран
    /// итогов: авторский секрет — самое редкое, веха — самое личное.
    var all: [Discovery] { secrets + riddles + milestones }

    /// Ничего не нашлось. `newKm` передаётся отдельно: «не нашёл ни одной
    /// печати» и «не открыл ни метра» — разные ответы.
    static func empty(tripId: UUID, newKm: Double = 0, newRegionIds: [String] = []) -> TripDiscoveries {
        TripDiscoveries(
            tripId: tripId, newKm: newKm, newRegionIds: newRegionIds,
            secrets: [], riddles: [], milestones: [])
    }
}

extension Milestone {
    /// Символ на медальоне вехи.
    ///
    /// Живёт у вехи, а не у экрана: печать рисуют «Атлас», карточка находки и
    /// экран итогов, и разъехаться этим трём нельзя. Веха, в отличие от
    /// загадки, своего символа в данных не несёт — она вычисляется, а не
    /// приходит из каталога.
    var symbol: SealSymbol {
        switch self {
        case .firstRegion, .threeRegionsDay: return .region
        case .easternmost, .westernmost, .northernmost, .southernmost: return .extreme
        case .above2000: return .altitude
        // «Ниже уровня моря» — это вода, а не гора: стрелка вниз к волне.
        case .belowSea: return .seaRoad
        case .countryBorder: return .border
        case .nightPass: return .night
        }
    }
}
