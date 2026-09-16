import Foundation
import CoreLocation

/// Решённая загадка.
struct RiddleSolve: Equatable {
    let riddle: Riddle
}

/// Решена ли загадка записанным треком.
///
/// Загадка решается ПРОЕЗДОМ и ничем больше: ни тапа по карте, ни ручного
/// ввода, ни «я тут был» — таких входов не существует. Радиус берётся у типа
/// (`RiddleType.reach`), потому что «мимо маяка» и «через перевал» — это
/// разные расстояния: перевал проезжают по дороге, а маяк видно с берега.
///
/// Считает тот же `TripRouteLocator.passes(near:)`, что и места: он уже умеет
/// «туда и обратно», и лишний проезд здесь безвреден — решение засчитывается
/// один раз, за него отвечает `Discovery.id(kind:key:)`.
///
/// `candidates` приходят уже отфильтрованными по ячейкам geohash-5 трека
/// (`TrackCells.geohash5`): поднимать все загадки бандла на каждую поездку
/// незачем.
enum RiddleMatcher {

    static func solved(track: [TrackPoint], candidates: [Riddle]) -> [RiddleSolve] {
        guard track.count > 1, !candidates.isEmpty else { return [] }
        return candidates.compactMap { riddle in
            let passes = TripRouteLocator.passes(
                near: riddle.coordinate, in: track, radius: riddle.type.reach)
            return passes.isEmpty ? nil : RiddleSolve(riddle: riddle)
        }
    }
}
