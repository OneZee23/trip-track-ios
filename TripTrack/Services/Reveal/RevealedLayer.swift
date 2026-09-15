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
struct RevealedLayer {
    let fine: [MKPolyline]
    let mid: [MKPolyline]
    let far: [MKPolyline]
    let cellCount: Int
    /// Длина открытых дорог. Считается по прогонам `fine` — то есть по тому,
    /// что реально открыто, а не по километрам поездок: сотый проезд по своей
    /// улице не открывает ничего.
    let openedKm: Double
    /// Регионы, которых коснулось открытое (ISO 3166-2). Пусто, если атлас не
    /// передан — итоги листа считает тот, кто атлас загрузил.
    let regionIds: Set<String>

    /// Шаг прореживания среднего уровня (≈250 м).
    static let midDegrees = 250.0 / 111_320.0
    /// Шаг прореживания дальнего уровня (≈1 км).
    static let farDegrees = 1_000.0 / 111_320.0

    static let empty = RevealedLayer(
        fine: [], mid: [], far: [], cellCount: 0, openedKm: 0, regionIds: []
    )

    var isEmpty: Bool { fine.isEmpty }

    static func build(tiles: [RevealedTile], atlas: RegionAtlas?) -> RevealedLayer {
        var runs: [[CLLocationCoordinate2D]] = []
        var cellCount = 0
        for tile in tiles {
            runs.append(contentsOf: tile.runs)
            cellCount += tile.cellSet.count
        }
        return build(runs: runs, cellCount: cellCount, atlas: atlas)
    }

    static func build(
        runs: [[CLLocationCoordinate2D]], cellCount: Int, atlas: RegionAtlas?
    ) -> RevealedLayer {
        var fine: [MKPolyline] = []
        var mid: [MKPolyline] = []
        var far: [MKPolyline] = []
        var metres: Double = 0
        var regions = Set<String>()

        for run in runs where run.count > 1 {
            fine.append(MKPolyline(coordinates: run, count: run.count))

            let midRun = RoadFog.decimate(run, minDegrees: midDegrees)
            if midRun.count > 1 { mid.append(MKPolyline(coordinates: midRun, count: midRun.count)) }
            let farRun = RoadFog.decimate(run, minDegrees: farDegrees)
            if farRun.count > 1 { far.append(MKPolyline(coordinates: farRun, count: farRun.count)) }

            metres += TripDistanceGate.totalDistance(run.map {
                TripDistanceGate.Sample(latitude: $0.latitude, longitude: $0.longitude, timestamp: nil)
            })

            if let atlas, let first = run.first,
               let region = atlas.region(containing: first) {
                regions.insert(region.id)
            }
        }

        return RevealedLayer(
            fine: fine, mid: mid, far: far,
            cellCount: cellCount,
            openedKm: metres / 1000,
            regionIds: regions
        )
    }
}
