import Foundation
import CoreLocation

/// Сетка открытого мира: 75 м, пакет на geohash-5.
///
/// Туман 0.7.0 знает про мир ровно две вещи — какие ячейки открыты и какой
/// формы коридор внутри них. Первое считается здесь, и считается ОДИН раз на
/// финише поездки: открытие вкладки читает готовый пакет из базы, а не гоняет
/// все поездки заново.
///
/// Почему ячейка 75 м, а не 150 м, как у `RoadFog`: у той сетка нужна была для
/// тепла (сколько раз проехал), и полкилометра туда-сюда ничего не решали. Здесь
/// ячейка — это граница видимого: коридор шириной ±50–75 м рисуется по ней, и
/// ячейка крупнее размазала бы улицу в пятно на квартал.
///
/// **Ячейка имеет смысл только внутри своего тайла.** Долгота масштабируется по
/// косинусу широты ЦЕНТРА тайла (иначе ячейка на широте Мурманска вытянулась бы
/// в прямоугольник вдвое шире своей высоты, и «75 м» перестало бы значить
/// расстояние), а значит шаг по долготе у соседних тайлов чуть разный.
/// Сравнивать `Cell` из разных тайлов нельзя — расхождение на стыке тайлов
/// меньше одной ячейки и туман его не видит.
enum RevealGrid {
    /// Сторона ячейки по широте, в градусах (≈75 м).
    static let cellDegrees = 0.000675
    /// Тайл — geohash-5 (≈4.9 × 4.9 км): столько открытого удобно читать и
    /// писать одной строкой базы.
    static let tilePrecision = 5
    /// Ячеек 75 м вдоль стороны тайла. Ровно 65.1 — то есть тайл может задеть
    /// 66–67 рядов, если его граница пришлась на середину ячейки; отсюда запас
    /// в `indexStride` ниже, а не «65 и ни ячейкой больше».
    static let tileCells = 65

    /// Широтный размер тайла geohash-5: 12 бит широты.
    static let tileLatSpan = 180.0 / 4096.0
    /// Долготный размер тайла geohash-5: 13 бит долготы.
    static let tileLonSpan = 360.0 / 8192.0

    /// Шаг упаковки локального индекса ячейки. Степень двойки с запасом над
    /// 67 рядами: `dr * 128 + dc` при `dr, dc < 128` даёт индекс ≤ 16 383,
    /// то есть влезает в `UInt16` втрое.
    static let indexStride: Int32 = 128

    /// Ниже этого косинус не опускается: на 87° широты ячейка иначе
    /// растянулась бы в градусах до бесконечности, а Int32 — не бесконечен.
    private static let minCosine = 0.05

    /// Шаг выборки вдоль отрезка, в долях ячейки. Треть ячейки — то же число,
    /// которым `RoadFog` ловит касание края: диагональный отрезок при нём не
    /// перешагивает ячейку.
    static let sampleStep = 0.33

    /// Дальше этого «отрезок» — не дорога, а пауза записи или прыжок GPS
    /// (≈33 км, как у `RoadFog`, только в ячейках втрое мельче). Освещать его
    /// значило бы прочертить коридор через всю область по прямой.
    static let maxSegmentCells = 440.0

    /// Ячейка сетки. Индексы глобальные по широте и ТАЙЛОВЫЕ по долготе —
    /// см. заголовок типа.
    struct Cell: Hashable {
        let row: Int32
        let col: Int32

        init(row: Int32, col: Int32) {
            self.row = row
            self.col = col
        }
    }

    /// Номер тайла в геохеш-решётке: 4096 полос по широте, 8192 по долготе.
    /// Считается арифметикой, а не строкой, — строка нужна только там, где
    /// ячейки пакуются в базу.
    struct TileIndex: Hashable {
        let lat: Int32
        let lon: Int32
    }

    // MARK: - Тайлы

    @inline(__always)
    static func tileIndex(for coordinate: CLLocationCoordinate2D) -> TileIndex {
        let lat = min(max(coordinate.latitude, -90), 90)
        let lon = min(max(coordinate.longitude, -180), 180)
        let latIndex = Int32(min(4095, max(0, ((lat + 90) / tileLatSpan).rounded(.down))))
        let lonIndex = Int32(min(8191, max(0, ((lon + 180) / tileLonSpan).rounded(.down))))
        return TileIndex(lat: latIndex, lon: lonIndex)
    }

    /// Ключ тайла — обычный geohash-5, тот же, которым пользуется остальное
    /// приложение (`GeohashEncoder`), чтобы ключ в базе читался глазами и
    /// сходился с кэшем геокодера.
    static func tileKey(for coordinate: CLLocationCoordinate2D) -> String {
        GeohashEncoder.encode(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            precision: tilePrecision
        )
    }

    /// Ключ по номеру тайла — через центр тайла, чтобы округление границы
    /// никогда не увело в соседний.
    static func tileKey(_ index: TileIndex) -> String {
        tileKey(for: center(ofTile: index))
    }

    @inline(__always)
    static func center(ofTile index: TileIndex) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: -90 + (Double(index.lat) + 0.5) * tileLatSpan,
            longitude: -180 + (Double(index.lon) + 0.5) * tileLonSpan
        )
    }

    /// Шаг ячейки по долготе в этом тайле — тот самый косинус широты центра.
    @inline(__always)
    static func lonDegrees(inTile index: TileIndex) -> Double {
        let centreLat = -90 + (Double(index.lat) + 0.5) * tileLatSpan
        return cellDegrees / max(cos(centreLat * .pi / 180), minCosine)
    }

    // MARK: - Ячейки

    @inline(__always)
    static func cell(for coordinate: CLLocationCoordinate2D) -> Cell {
        cell(for: coordinate, in: tileIndex(for: coordinate))
    }

    @inline(__always)
    static func cell(for coordinate: CLLocationCoordinate2D, in tile: TileIndex) -> Cell {
        let lonStep = lonDegrees(inTile: tile)
        let row = Int32((coordinate.latitude / cellDegrees).rounded(.down))
        let col = Int32((coordinate.longitude / lonStep).rounded(.down))
        return Cell(row: row, col: col)
    }

    /// Центр ячейки — нужен рендереру (нарисовать ячейку) и тестам (взять
    /// координату, про которую точно известно, в какой она ячейке).
    static func center(of cell: Cell, in tile: String) -> CLLocationCoordinate2D {
        let origin = tileOrigin(tile)
        return CLLocationCoordinate2D(
            latitude: (Double(cell.row) + 0.5) * cellDegrees,
            longitude: (Double(cell.col) + 0.5) * origin.lonStep
        )
    }

    // MARK: - Ход по линии

    /// Каждая ячейка, которую задевает ломаная, по порядку — вместе с точкой
    /// НА самой линии, попавшей в эту ячейку.
    ///
    /// Превью-полилиния упрощена RDP: на трассе между соседними вершинами
    /// бывают километры, и отнести весь отрезок к ячейке под его серединой
    /// (первая попытка `RoadFog`) значило бы оставить трассу незастолблённой.
    /// Поэтому отрезок проходится с шагом в треть ячейки.
    ///
    /// Разрыв записи не сшивается: отрезок длиннее `maxSegmentCells`
    /// пропускается целиком, и вызывающий увидит это как скачок между двумя
    /// соседними точками (см. `RevealBuilder.runGapMetres`).
    static func walkCells(
        _ line: [CLLocationCoordinate2D],
        _ body: (Cell, CLLocationCoordinate2D) -> Void
    ) {
        guard let first = line.first else { return }
        guard line.count > 1 else {
            body(cell(for: first), first)
            return
        }

        var previous: Cell?
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i]
            guard a.latitude.isFinite, a.longitude.isFinite,
                  b.latitude.isFinite, b.longitude.isFinite else { continue }
            let tile = tileIndex(for: a)
            let lonStep = lonDegrees(inTile: tile)
            let span = max(
                abs(b.latitude - a.latitude) / cellDegrees,
                abs(b.longitude - a.longitude) / lonStep
            )
            guard span.isFinite, span <= maxSegmentCells else { continue }

            let steps = max(1, min(4096, Int((span / sampleStep).rounded(.up))))
            let dLat = b.latitude - a.latitude
            let dLon = b.longitude - a.longitude
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let point = CLLocationCoordinate2D(
                    latitude: a.latitude + dLat * t,
                    longitude: a.longitude + dLon * t
                )
                let here = cell(for: point)
                guard here != previous else { continue }
                previous = here
                body(here, point)
            }
        }
    }

    // MARK: - Код ячеек

    /// Начало тайла: с какого ряда и столбца считаются локальные индексы и
    /// каким шагом идёт долгота. Берётся из границ geohash-строки, поэтому
    /// `encode`/`decode` не нуждаются ни в чём, кроме ключа.
    static func tileOrigin(_ tile: String) -> (row0: Int32, col0: Int32, lonStep: Double) {
        let box = GeohashEncoder.decode(tile)
        let centreLat = (box.lat.lowerBound + box.lat.upperBound) / 2
        let lonStep = cellDegrees / max(cos(centreLat * .pi / 180), minCosine)
        let row0 = Int32((box.lat.lowerBound / cellDegrees).rounded(.down))
        let col0 = Int32((box.lon.lowerBound / lonStep).rounded(.down))
        return (row0, col0, lonStep)
    }

    /// Ячейки тайла в компактном виде: локальный индекс `UInt16`, сортировка,
    /// дельта, varint. Подряд идущие ячейки (а открытая дорога — это ряд
    /// подряд идущих ячеек) дают дельту 1, то есть один байт на ячейку.
    ///
    /// Ячейка, не принадлежащая тайлу, молча выбрасывается: её локальный
    /// индекс не существует, а записать «чужой» индекс значило бы вернуть при
    /// чтении ячейку в другом месте карты.
    static func encode(_ cells: [Cell], in tile: String) -> Data {
        let origin = tileOrigin(tile)
        var indices: [UInt32] = []
        indices.reserveCapacity(cells.count)
        for cell in cells {
            let dr = cell.row - origin.row0
            let dc = cell.col - origin.col0
            guard dr >= 0, dr < indexStride, dc >= 0, dc < indexStride else { continue }
            indices.append(UInt32(dr * indexStride + dc))
        }
        indices.sort()

        var data = Data()
        data.reserveCapacity(indices.count + 2)
        var previous: UInt32 = 0
        var isFirst = true
        for index in indices {
            if !isFirst && index == previous { continue }
            appendVarint(isFirst ? index : index - previous, to: &data)
            previous = index
            isFirst = false
        }
        return data
    }

    static func decode(_ data: Data, in tile: String) -> [Cell] {
        guard !data.isEmpty else { return [] }
        let origin = tileOrigin(tile)
        var cells: [Cell] = []
        var value: UInt32 = 0
        var shift: UInt32 = 0
        var accumulated: UInt32 = 0
        var isFirst = true

        for byte in data {
            value |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 != 0 {
                shift += 7
                if shift > 28 { return cells }   // битый блок — отдаём, что успели
                continue
            }
            accumulated = isFirst ? value : accumulated &+ value
            isFirst = false
            let dr = Int32(accumulated / UInt32(indexStride))
            let dc = Int32(accumulated % UInt32(indexStride))
            cells.append(Cell(row: origin.row0 + dr, col: origin.col0 + dc))
            value = 0
            shift = 0
        }
        return cells
    }

    @inline(__always)
    private static func appendVarint(_ value: UInt32, to data: inout Data) {
        var rest = value
        while rest >= 0x80 {
            data.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        data.append(UInt8(rest))
    }
}
