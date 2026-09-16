import Foundation
import CoreLocation

/// Секрет, найденный на треке.
struct SecretMatch: Equatable {
    let secretId: String
    /// Центр совпавшей ячейки — единственная координата, какая у нас есть:
    /// настоящей точки секрета в бандле нет и не будет.
    let coordinate: CLLocationCoordinate2D
    let symbol: SealSymbol

    static func == (lhs: SecretMatch, rhs: SecretMatch) -> Bool {
        lhs.secretId == rhs.secretId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.symbol == rhs.symbol
    }
}

/// Проехал ли трек мимо авторского секрета.
///
/// Секрет закрыт полностью: в бандле только 32-битные усечения
/// `SHA-256(salt ‖ geohash7)`, и обратного хода из них нет. Поэтому вопрос
/// задаётся наоборот — не «где секрет», а «не совпал ли хеш ячейки, в которой
/// я был». Чистая функция: ни базы, ни сети, ни разговора с человеком, и
/// зовётся она только после финиша.
///
/// Две проверки, а не одна. **Хеш** отвечает «ячейка та самая», но ячейка —
/// это 150 метров, а усечение до 32 бит на десятках тысяч ячеек длинной
/// поездки однажды даст ложное совпадение просто по теории вероятностей.
/// **`reach`** отвечает «и я действительно был рядом»: трек обязан пройти в
/// `record.reach` от центра совпавшей ячейки, а считает это тот же
/// `TripRouteLocator.passes(near:)`, которым места считают проезды.
///
/// Соседи берутся у ячеек ТРЕКА: секрет у границы своей ячейки виден из
/// соседней, и без этого проезд в двадцати метрах от него не засчитался бы.
/// Площадному секрету (`polygon`) соседи не нужны и `reach` не проверяется
/// вовсе — он и так покрывает свои ячейки целиком, а ободок из соседей
/// раздул бы его на 150 м во все стороны.
enum SecretMatcher {

    static func matches(track: [TrackPoint], catalog: [SecretRecord], salt: String) -> [SecretMatch] {
        guard !track.isEmpty, !catalog.isEmpty else { return [] }

        let trackCells = TrackCells.geohash7(track)
        guard !trackCells.isEmpty else { return [] }

        var candidateCells = trackCells
        for cell in trackCells {
            candidateCells.formUnion(GeohashEncoder.neighbors(of: cell))
        }

        // Хеш → ячейки. Два стола: точечный секрет ищется среди ячеек трека и
        // их соседей, площадной — только среди ячеек самого трека.
        // Ячейки перебираются отсортированными, чтобы при совпадении
        // нескольких ответ не зависел от расклада множества.
        var byHash: [UInt32: [String]] = [:]
        var byHashTrackOnly: [UInt32: [String]] = [:]
        for cell in candidateCells.sorted() {
            let hash = SecretHash.truncated(salt: salt, geohash7: cell)
            byHash[hash, default: []].append(cell)
            if trackCells.contains(cell) {
                byHashTrackOnly[hash, default: []].append(cell)
            }
        }

        var result: [SecretMatch] = []
        for record in catalog {
            let table = record.polygon ? byHashTrackOnly : byHash
            guard let cell = firstHit(for: record, in: table, track: track) else { continue }
            result.append(SecretMatch(
                secretId: record.id,
                coordinate: GeohashEncoder.centerCoordinate(of: cell),
                symbol: record.symbol
            ))
        }
        return result
    }

    /// Первая ячейка секрета, которая прошла обе проверки. Один секрет — одна
    /// печать, сколько бы его ячеек трек ни задел.
    private static func firstHit(
        for record: SecretRecord,
        in table: [UInt32: [String]],
        track: [TrackPoint]
    ) -> String? {
        for hash in record.hashes {
            guard let cells = table[hash] else { continue }
            for cell in cells {
                if record.polygon { return cell }
                let centre = GeohashEncoder.centerCoordinate(of: cell)
                if !TripRouteLocator.passes(near: centre, in: track, radius: record.reach).isEmpty {
                    return cell
                }
            }
        }
        return nil
    }
}
