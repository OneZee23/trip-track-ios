import Foundation
import CoreLocation

/// «Журнал первооткрывателя» — то, что показывает развёрнутый лист «Атласа»
/// (спека §5): три группы — открытое, находки, загадки рядом.
///
/// Значение, а не вычисление в `body`. Считается один раз на загрузке
/// (`MyMapViewModel.reload` / `reloadDiscoveries`) и дальше только печатается:
/// лист перерисовывается на каждый кадр перетаскивания ручки, а здесь и
/// сортировка находок, и расстояние от открытой территории до каждого круга.
/// Тот же приём, которым `MapRegionStat.firstVisited` считается в
/// `MapExploration.build`, а не на экране.
struct Journal: Equatable {

    /// Загадка рядом: про что она и сколько до её круга.
    struct NearbyRiddle: Identifiable, Equatable {
        /// `Riddle.id` — «<type>:<geohash7>», он же id подсказки на карте.
        let id: String
        let type: RiddleType
        /// До КРАЯ круга, в метрах. Ноль — открытое уже внутри круга.
        ///
        /// До края, а не до середины: середина круга смещена нарочно
        /// (`RiddleHint.offsetCentre`), и число «до центра» обещало бы
        /// точность, которой у круга нет. А `nil` было бы четвёртым
        /// состоянием на ровном месте: подсказок без открытой территории не
        /// бывает вовсе — `RiddleHint.plan` не выдаёт их без центроидов.
        let metresToEdge: Double
    }

    /// Открыто всего, километрами слоя (`RevealedLayer.openedKm`).
    ///
    /// Километрами, а не метрами: слой копит их так, а второй перевод по
    /// дороге на экран однажды разошёлся бы с шапкой. На экран это число
    /// попадает только через `Measure`.
    var openedKm: Double = 0
    /// Регионы в том же порядке, в каком их отдал `MapExploration` — по
    /// убыванию пройденного. Перекладывать их по дате первого въезда значило
    /// бы завести второй порядок для того же списка.
    var regions: [MapRegionStat] = []
    /// Печати, свежая первая.
    var finds: [Discovery] = []
    /// Не больше трёх (`RiddleHint.maxShown`) — сколько дал план подсказок,
    /// столько и здесь: круги на карте и строки в журнале обязаны совпадать.
    var riddles: [NearbyRiddle] = []

    var isEmpty: Bool { regions.isEmpty && finds.isEmpty && riddles.isEmpty }

    static let empty = Journal()
}

/// Сборка журнала — чистой функцией, из УЖЕ прочитанного.
///
/// Ни базы, ни каталога, ни атласа: регионы приходят из `MapExploration`
/// (там же посчитаны их имена и даты первого въезда), километры — из
/// `RevealedLayer`, печати — из `DiscoveryStore`, круги — из
/// `RiddleHint.plan`. Отдельная дверь нужна ровно ради теста: расстояние до
/// края круга и порядок находок проверяются числами, а не глазами на экране,
/// где круг нарисован в масштабе страны.
enum JournalBuilder {

    static func build(
        exploration: MapExploration,
        revealed: RevealedLayer,
        seals: [Discovery],
        hints: [RiddleHint]
    ) -> Journal {
        Journal(
            openedKm: revealed.openedKm,
            regions: exploration.regions,
            finds: sortedFinds(seals),
            riddles: nearby(hints: hints, centroids: Array(revealed.regionCentroids.values))
        )
    }

    /// Свежая печать первой. Ничья по дате решается id, а не порядком выборки:
    /// финиш кладёт секрет, загадку и веху одной датой, и без второго ключа
    /// сетка тасовалась бы от перезагрузки к перезагрузке.
    static func sortedFinds(_ seals: [Discovery]) -> [Discovery] {
        seals.sorted { lhs, rhs in
            if lhs.foundAt == rhs.foundAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.foundAt > rhs.foundAt
        }
    }

    /// Расстояние от открытой территории до КРАЯ круга: `max(0, d − радиус)`,
    /// где `d` — до ближайшего центроида открытого региона.
    ///
    /// От центроидов, а не от текущего местоположения: «Атлас» не спрашивает
    /// GPS вовсе (`NoLiveSecretPromptsTests`), да и вопрос у строки не «сколько
    /// ехать сейчас», а «далеко ли это от мест, где я бываю» — тот же вопрос,
    /// по которому три круга и выбраны (`RiddleHint.plan`).
    ///
    /// Центроидов нет — расстояния нет, и это ноль: подсказки без открытой
    /// территории не бывает, а падать на пустом слое нельзя.
    static func nearby(
        hints: [RiddleHint], centroids: [CLLocationCoordinate2D]
    ) -> [Journal.NearbyRiddle] {
        guard !centroids.isEmpty else {
            return hints.map {
                Journal.NearbyRiddle(id: $0.id, type: $0.type, metresToEdge: 0)
            }
        }
        return hints.map { hint in
            let toCentre = RiddleHint.distanceToNearest(of: hint.centre, among: centroids)
            return Journal.NearbyRiddle(
                id: hint.id, type: hint.type,
                metresToEdge: max(0, toCentre - hint.radiusMetres))
        }
    }
}
