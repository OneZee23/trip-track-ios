import Foundation
import CoreLocation
import MapKit

/// Один тайл открытого мира, как он лежит в базе.
///
/// **Формат `geometry`.** Несколько прогонов в одном блобе, кадрами:
/// `UInt32` — сколько прогонов (little-endian), затем по `UInt32` на прогон —
/// сколько в нём точек, затем сами точки подряд, парами `Float32`
/// (`Trip.encodePolyline`, тот же кодек, которым живёт превью поездки).
/// Разделять прогоны маркером нельзя — любое значение координаты законно;
/// поэтому длины идут заголовком, а не разделителем.
struct RevealedTile {
    let key: String
    let cells: Data
    let geometry: Data
    let updatedAt: Date

    var cellSet: Set<RevealGrid.Cell> { Set(RevealGrid.decode(cells, in: key)) }
    var runs: [[CLLocationCoordinate2D]] { RevealedTile.decodeRuns(geometry) }

    static func encodeRuns(_ runs: [[CLLocationCoordinate2D]]) -> Data {
        let kept = runs.filter { $0.count > 1 }
        var data = Data()
        var count = UInt32(kept.count).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for run in kept {
            var length = UInt32(run.count).littleEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        }
        for run in kept { data.append(Trip.encodePolyline(run)) }
        return data
    }

    static func decodeRuns(_ data: Data) -> [[CLLocationCoordinate2D]] {
        guard data.count >= 4 else { return [] }
        let bytes = [UInt8](data)
        func uint32(at offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        let count = Int(uint32(at: 0))
        guard count > 0, bytes.count >= 4 + count * 4 else { return [] }
        var lengths: [Int] = []
        lengths.reserveCapacity(count)
        var total = 0
        for i in 0..<count {
            let length = Int(uint32(at: 4 + i * 4))
            lengths.append(length)
            total += length
        }
        var offset = 4 + count * 4
        guard bytes.count >= offset + total * 8 else { return [] }

        var runs: [[CLLocationCoordinate2D]] = []
        runs.reserveCapacity(count)
        for length in lengths {
            let chunk = data.subdata(in: offset..<(offset + length * 8))
            runs.append(Trip.decodePolyline(chunk))
            offset += length * 8
        }
        return runs
    }
}

/// Снимок открытого мира для рендерера — иммутабельный, строится вне главного
/// актёра.
///
/// Три уровня детали, потому что коридор на масштабе страны — это вена шириной
/// в пиксель: рисовать её по точкам через 75 м значит платить за каждую сотню
/// километров тысячей вершин, которых никто не увидит. 250 м и 1 км — те же
/// прогоны, прорежённые `RoadFog.decimate`.
///
/// **Уровень — ОДИН оверлей (`MKMultiPolyline`), а не список полилиний.**
/// Прогонов у зрелой библиотеки десятки тысяч (каждый новый фронт в тайле
/// добавляет свой), и по оверлею на прогон значило бы тысячи оверлеев и
/// тысяч вызовов рендерера на кадр. Второе, не менее важное: собранные в один
/// путь прогоны композитятся за ОДИН проход, и намеренный «шаг внахлёст» на
/// границе уже открытого (≤ 75 м, см. `RevealBuilder`) перестаёт быть видимым
/// швом — альфа применяется к объединению, а не к каждой линии отдельно.
struct RevealedLayer {
    let fine: MKMultiPolyline
    let mid: MKMultiPolyline
    let far: MKMultiPolyline
    let cellCount: Int
    /// Длина открытых дорог. Считается по прогонам `fine` — то есть по тому,
    /// что реально открыто, а не по километрам поездок: сотый проезд по своей
    /// улице не открывает ничего.
    let openedKm: Double
    /// Регионы, которых коснулось открытое (ISO 3166-2). Пусто, если атлас не
    /// передан — итоги листа считает тот, кто атлас загрузил.
    let regionIds: Set<String>
    /// Открытые километры ПО РЕГИОНАМ — те же самые, что в `openedKm`, только
    /// разложенные. Сумма сходится с итогом по построению: и то и другое
    /// набирается ОДНИМ проходом по прогонам, одним шагом и одним якорем.
    ///
    /// Второго счёта открытого в приложении нет и быть не может. До 0.7.0 их
    /// было два: шапка печатала эту длину прогонов по сетке 75 м, а строка
    /// региона — ячейки `RoadFog` по сетке 150 м, и сумма строк с шапкой не
    /// сходилась никогда. Ровно та поломка, из-за которой километры поездки
    /// собрали в `TripDistanceGate`, а высоту вынули из `GarageFormat.odometer`.
    var regionKm: [String: Double] = [:]
    /// Середина ОТКРЫТОЙ части региона — туда карта ставит его подпись.
    ///
    /// Не центр региона из атласа: подпись обязана стоять там, где человек
    /// был, а не посреди темноты в географическом центре края, до которого он
    /// не доезжал. Считается здесь, а не на экране, потому что здешний цикл
    /// уже спрашивает атлас про точки прогонов — второй такой цикл был бы
    /// вторым проходом по всей библиотеке ради одной точки.
    ///
    /// И это ТОЧКА НА ПРОГОНЕ, а не среднее координат. Среднее двух далёких
    /// кусков (дача на севере, море на юге) попадает ровно между ними, то есть
    /// в темноту, — ту самую, которой доккоммент обещает избегать. Поэтому
    /// среднее считается по всем точкам прогонов, а потом ПРИТЯГИВАЕТСЯ к
    /// ближайшей из них.
    var regionCentroids: [String: CLLocationCoordinate2D] = [:]

    /// Три уровня детали — какой рисовать, решает зум
    /// (`FogVeilRenderer.lod(for:)`).
    enum LOD: CaseIterable { case fine, mid, far }

    /// Открыто в этом регионе. Ноль — регион атласа, до которого не доезжали,
    /// и это законный ответ, а не отсутствие данных.
    func openedKm(regionId: String) -> Double { regionKm[regionId] ?? 0 }

    func polylines(for lod: LOD) -> [MKPolyline] {
        switch lod {
        case .fine: return fine.polylines
        case .mid:  return mid.polylines
        case .far:  return far.polylines
        }
    }

    /// Через сколько точек прогона берётся проба для подписи региона. Точки
    /// лежат через ≈75 м, то есть проба — примерно через 375 м: чаще незачем
    /// (подпись стоит одна на край), реже — и короткий прогон не даст ни одной.
    static let centroidSampleStride = 5

    /// Шаг прореживания среднего уровня (≈250 м).
    static let midDegrees = 250.0 / 111_320.0
    /// Шаг прореживания дальнего уровня (≈1 км).
    static let farDegrees = 1_000.0 / 111_320.0

    static let empty = RevealedLayer(
        fine: MKMultiPolyline(), mid: MKMultiPolyline(), far: MKMultiPolyline(),
        cellCount: 0, openedKm: 0, regionIds: []
    )

    var isEmpty: Bool { fine.polylines.isEmpty }

    static func build(tiles: [RevealedTile], atlas: RegionAtlas?) -> RevealedLayer {
        var runs: [[CLLocationCoordinate2D]] = []
        var cellCount = 0
        for tile in tiles {
            runs.append(contentsOf: tile.runs)
            cellCount += tile.cellSet.count
        }
        return build(runs: runs, cellCount: cellCount, atlas: atlas)
    }

    /// Ближайшая к точке проба — или сама точка, если проб не осталось.
    ///
    /// Сравнение по градусам, не по метрам: нужен МИНИМУМ, а не расстояние, и
    /// косинус широты внутри одного края его не переставляет.
    static func nearest(
        to target: CLLocationCoordinate2D, among samples: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D {
        var best = target
        var bestDistance = Double.infinity
        for sample in samples {
            let dLat = sample.latitude - target.latitude
            let dLon = (sample.longitude - target.longitude)
                * cos(target.latitude * .pi / 180)
            let distance = dLat * dLat + dLon * dLon
            if distance < bestDistance {
                bestDistance = distance
                best = sample
            }
        }
        return best
    }

    static func build(
        runs: [[CLLocationCoordinate2D]], cellCount: Int, atlas: RegionAtlas?
    ) -> RevealedLayer {
        var fine: [MKPolyline] = []
        var mid: [MKPolyline] = []
        var far: [MKPolyline] = []
        var metres: Double = 0
        var regionMetres: [String: Double] = [:]
        var regions = Set<String>()
        var centroidSums: [String: (lat: Double, lon: Double, count: Double)] = [:]
        var centroidSamples: [String: [CLLocationCoordinate2D]] = [:]

        for run in runs where run.count > 1 {
            fine.append(MKPolyline(coordinates: run, count: run.count))

            let midRun = RoadFog.decimate(run, minDegrees: midDegrees)
            if midRun.count > 1 { mid.append(MKPolyline(coordinates: midRun, count: midRun.count)) }
            let farRun = RoadFog.decimate(run, minDegrees: farDegrees)
            if farRun.count > 1 { far.append(MKPolyline(coordinates: farRun, count: farRun.count)) }

            // Длина, регионы, подпись и километры по регионам — ОДНИМ проходом
            // и одним якорем. Второй цикл со своим порогом однажды разошёлся бы
            // с первым, и разошлись бы ровно те два числа, которые человек
            // видит на одном экране (шапка и строка региона).
            //
            // Пробы региона по всему прогону, а не два конца: прогон длиной с
            // тайл (5–7 км) умеет пересечь границу региона, и по концам
            // соседний край либо не появился бы в итогах вовсе, либо получил
            // бы всю тяжесть прогона, лежащего в чужом. Между пробами регион
            // держится прежний — то есть километры ложатся с точностью до
            // ≈375 м дороги; спрашивать атлас на каждой точке значило бы
            // впятеро больше запросов ради разницы, которой не видно в строке.
            var currentRegion: String?
            var anchor: CLLocationCoordinate2D?
            for (i, point) in run.enumerated() {
                if atlas != nil, i % centroidSampleStride == 0 || i == run.count - 1 {
                    currentRegion = atlas?.region(containing: point)?.id
                    if let id = currentRegion {
                        regions.insert(id)
                        var sum = centroidSums[id] ?? (0, 0, 0)
                        sum.lat += point.latitude
                        sum.lon += point.longitude
                        sum.count += 1
                        centroidSums[id] = sum
                        centroidSamples[id, default: []].append(point)
                    }
                }

                guard let from = anchor else { anchor = point; continue }
                let step = CLLocation(latitude: point.latitude, longitude: point.longitude)
                    .distance(from: CLLocation(latitude: from.latitude, longitude: from.longitude))
                // Тот же шаг и тот же перенос якоря, что у `TripDistanceGate
                // .totalDistance`: километры открытого обязаны набираться тем
                // же способом, что и километры поездки.
                guard step >= TripDistanceGate.minStep else { continue }
                if TripDistanceGate.isPlausibleSegment(meters: step, dt: 0) {
                    metres += step
                    if let id = currentRegion { regionMetres[id, default: 0] += step }
                }
                anchor = point
            }
        }

        return RevealedLayer(
            fine: MKMultiPolyline(fine), mid: MKMultiPolyline(mid), far: MKMultiPolyline(far),
            cellCount: cellCount,
            openedKm: metres / 1000,
            regionIds: regions,
            regionKm: regionMetres.mapValues { $0 / 1000 },
            regionCentroids: centroidSums.reduce(into: [:]) { out, entry in
                let mean = CLLocationCoordinate2D(
                    latitude: entry.value.lat / entry.value.count,
                    longitude: entry.value.lon / entry.value.count
                )
                out[entry.key] = nearest(to: mean, among: centroidSamples[entry.key] ?? [])
            }
        )
    }
}
