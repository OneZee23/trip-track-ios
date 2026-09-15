import Foundation
import CoreLocation

/// Что поездка открыла НОВОГО — ячейки и геометрия коридора, по тайлам.
///
/// `cells` — только свежие ячейки (те, которых не было в открытом до этой
/// поездки), `runs` — прогоны линии по этим ячейкам, шагом примерно в ячейку.
struct TilePatch {
    var cells: Set<RevealGrid.Cell> = []
    var runs: [[CLLocationCoordinate2D]] = []

    var isEmpty: Bool { cells.isEmpty && runs.isEmpty }
}

/// Превью-полилиния поездки → новые ячейки и коридоры, по тайлам.
///
/// Приём — «застолбить и отрезать» (`claim & cut`) из `RoadFog.build`, и он тут
/// главный: шестьдесят проездов по одной улице должны оставить ОДНУ линию, а не
/// шестьдесят, разъехавшихся шумом GPS в кляксу. Первая поездка через ячейку
/// владеет геометрией; следующая, идущая по уже открытому, не даёт ни ячеек, ни
/// прогонов — и её тайл в ответе вообще не появляется.
///
/// Функция чистая: всё, что она знает про уже открытое, приходит замыканием
/// `claimed`. Поэтому одна и та же сборка работает и на финише поездки (открытое
/// из базы), и во «временном тумане» экрана поездки (открытое копится в памяти,
/// в базу не пишется вовсе).
enum RevealBuilder {
    /// Дальше этого две соседние точки хода — не шаг по дороге, а склейка
    /// через пропущенный разрыв записи: прогон рвётся. Три ячейки с запасом на
    /// диагональ.
    static let runGapMetres: Double = 300

    /// Шаг прореживания прогона. Точки хода и так лежат по одной на ячейку;
    /// порог чуть меньше ячейки убирает только «уголки» — два касания подряд у
    /// самой границы, — не трогая форму улицы.
    static let runStepDegrees = RevealGrid.cellDegrees * 0.6

    /// Новые ячейки и прогоны поездки относительно уже открытого.
    ///
    /// `claimed` спрашивается по ключу тайла и ровно один раз на тайл —
    /// вызывающий волен ходить в базу, кэш это уже учитывает.
    static func patches(
        for coords: [CLLocationCoordinate2D],
        claimed: (String) -> Set<RevealGrid.Cell>
    ) -> [String: TilePatch] {
        guard coords.count >= 2 else { return [:] }

        // MARK: Ход по линии
        var points: [CLLocationCoordinate2D] = []
        var cells: [RevealGrid.Cell] = []
        var tiles: [String] = []
        RevealGrid.walkCells(coords) { cell, point in
            points.append(point)
            cells.append(cell)
            tiles.append(RevealGrid.tileKey(for: point))
        }
        guard points.count >= 2 else { return [:] }

        // MARK: Кто здесь впервые
        var claimedCache: [String: Set<RevealGrid.Cell>] = [:]
        var fresh = [Bool](repeating: false, count: points.count)
        var patches: [String: TilePatch] = [:]

        for i in 0..<points.count {
            let key = tiles[i]
            if claimedCache[key] == nil { claimedCache[key] = claimed(key) }
            guard claimedCache[key]?.contains(cells[i]) != true else { continue }
            // Доступ по месту (`default:` + `_modify`): `patches[key]` отдавал
            // бы КОПИЮ множества на каждую ячейку, и вставка била бы по CoW —
            // внутри тайла это квадрат от числа ячеек.
            fresh[i] = patches[key, default: TilePatch()].cells.insert(cells[i]).inserted
        }

        // MARK: Какие шаги рисуются
        let steps = points.count - 1
        var broken = [Bool](repeating: false, count: steps)
        var draw = [Bool](repeating: false, count: steps)
        for i in 0..<steps {
            broken[i] = distance(points[i], points[i + 1]) > runGapMetres
            draw[i] = fresh[i] || fresh[i + 1]
        }
        // Шаг, соседний с нарисованным, тоже рисуется: иначе там, где эта
        // поездка передаёт дорогу той, что застолбила её первой, осталась бы
        // дыра шириной в ячейку.
        var extended = draw
        for i in 0..<steps where draw[i] {
            if i > 0 { extended[i - 1] = true }
            if i + 1 < steps { extended[i + 1] = true }
        }
        for i in 0..<steps where broken[i] { extended[i] = false }

        // MARK: Прогоны — по тайлам, с разрывами
        var run: [CLLocationCoordinate2D] = []
        var runTile = ""
        func flush() {
            defer { run = []; runTile = "" }
            guard run.count > 1, !runTile.isEmpty else { return }
            let thinned = tileLine(run, stepDegrees: runStepDegrees)
            guard thinned.count > 1 else { return }
            patches[runTile, default: TilePatch()].runs.append(thinned)
        }

        for i in 0..<steps {
            guard extended[i] else {
                flush()
                continue
            }
            if tiles[i] != runTile {
                flush()
                run = [points[i]]
                runTile = tiles[i]
            }
            run.append(points[i + 1])
        }
        flush()

        return patches.filter { !$0.value.isEmpty }
    }

    /// Прореживание по шагу: радиальное, как `RoadFog.decimate`, и по той же
    /// причине — для маски и для зума, где половина точек меньше пикселя, RDP
    /// стоит дороже, чем стоит его результат.
    static func tileLine(
        _ coords: [CLLocationCoordinate2D], stepDegrees: Double
    ) -> [CLLocationCoordinate2D] {
        RoadFog.decimate(coords, minDegrees: stepDegrees)
    }

    @inline(__always)
    private static func distance(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
