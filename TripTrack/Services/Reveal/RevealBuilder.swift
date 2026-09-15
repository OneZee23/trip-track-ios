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
/// Владение считается по ОКРЕСТНОСТИ ячейки, а не по самой ячейке: ячейка
/// 75 м, а разброс GPS на одной и той же улице — те же десятки метров, поэтому
/// «застолбить» обязан квадрат 3×3 вокруг занятой ячейки. Ячейки при этом
/// добавляются по-прежнему по себе одной — растёт открытое, а не рисуется
/// линия.
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

    /// Через сколько ячеек хода СВОЯ же ячейка начинает считаться чужой.
    ///
    /// Восемь соседей смотрят и на то, что застолбила эта самая поездка, —
    /// иначе «туда и обратно» одним треком по-прежнему рисует две нитки в
    /// двадцати пяти метрах. Но сравнивать со всем, что уже пройдено, нельзя:
    /// ячейка i-1 — сосед ячейки i по определению, и запрет застопорил бы
    /// вообще всё. Шесть ячеек хода (≈450 м) — та дистанция, на которой «я всё
    /// ещё еду по этой улице» кончается, а «я вернулся по ней же» начинается.
    static let selfClaimGapCells = 6

    /// На сколько шагов прогон вылезает за прочищенное.
    ///
    /// До 0.7.0 был один шаг: на границе с уже открытым иначе оставалась дыра в
    /// ячейку. С запретом по соседям граница отодвинулась — новая улица
    /// начинает рисоваться, только отойдя от чужой на две ячейки, — и нахлёст
    /// обязан покрыть ровно это. Два шага (≈150 м) целиком лежат внутри
    /// коридора ±50 м уже открытой дороги, то есть новой геометрии на карте не
    /// добавляют.
    static let runOverlapSteps = 2

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
        //
        // «Ячейку добавляем» и «прогон рисуем» — РАЗНЫЕ вопросы, и это главное
        // решение всей сборки. Ячейка 75 м, а второй проезд по той же улице
        // уходит шумом GPS за её границу — и до 0.7.0 получал свой прогон в
        // двадцати пяти метрах от чужого. На улице это три параллельные нитки,
        // а под непрозрачной вуалью ещё и расплывшийся втрое коридор: дыру и
        // линию рисуют одни и те же прогоны.
        //
        // Поэтому ячейка по-прежнему столбится по `fresh` (иначе туман
        // перестал бы расти), а рисуется только та, у которой НИ ОДИН из
        // восьми соседей не занят — ни прежними поездками, ни этой же (см.
        // `selfClaimGapCells`). Второй дедуп специально для жилки завёл бы
        // второй источник геометрии, а вся 0.7.0 держится на том, что у дыры и
        // у линии источник один.
        var claimedCache: [String: Set<RevealGrid.Cell>] = [:]
        var mine: [String: [RevealGrid.Cell: Int]] = [:]
        var fresh = [Bool](repeating: false, count: points.count)
        var paint = [Bool](repeating: false, count: points.count)
        var patches: [String: TilePatch] = [:]

        for i in 0..<points.count {
            let key = tiles[i]
            if claimedCache[key] == nil { claimedCache[key] = claimed(key) }
            let already = claimedCache[key] ?? []
            guard !already.contains(cells[i]) else { continue }
            // Доступ по месту (`default:` + `_modify`): `patches[key]` отдавал
            // бы КОПИЮ множества на каждую ячейку, и вставка била бы по CoW —
            // внутри тайла это квадрат от числа ячеек.
            fresh[i] = patches[key, default: TilePatch()].cells.insert(cells[i]).inserted
            guard fresh[i] else { continue }
            paint[i] = !neighbourClaimed(
                of: cells[i], at: i, claimed: already, mine: mine[key] ?? [:])
            mine[key, default: [:]][cells[i]] = i
        }

        // MARK: Какие шаги рисуются
        let steps = points.count - 1
        var broken = [Bool](repeating: false, count: steps)
        var draw = [Bool](repeating: false, count: steps)
        for i in 0..<steps {
            broken[i] = distance(points[i], points[i + 1]) > runGapMetres
            draw[i] = paint[i] || paint[i + 1]
        }
        // Шаги вокруг нарисованного тоже рисуются: иначе там, где эта поездка
        // принимает дорогу у той, что застолбила её первой, осталась бы дыра.
        var extended = draw
        for i in 0..<steps where draw[i] {
            for step in 1...runOverlapSteps {
                if i >= step { extended[i - step] = true }
                if i + step < steps { extended[i + step] = true }
            }
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

    /// Занят ли хоть один из восьми соседей ячейки — прежними поездками или
    /// этой же, но давно (`selfClaimGapCells`).
    ///
    /// Соседей ищем в ТОМ ЖЕ тайле: шаг по долготе у ячейки считается от
    /// косинуса широты центра тайла, и у соседнего тайла он другой — сравнивать
    /// `Cell` из разных тайлов нельзя (см. `RevealGrid`). На стыке тайлов это
    /// даёт одну ячейку, у которой соседей с той стороны не видно; расхождение
    /// меньше ячейки, и туман его не видит.
    static func neighbourClaimed(
        of cell: RevealGrid.Cell,
        at index: Int,
        claimed: Set<RevealGrid.Cell>,
        mine: [RevealGrid.Cell: Int]
    ) -> Bool {
        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                let neighbour = RevealGrid.Cell(
                    row: cell.row + Int32(dr), col: cell.col + Int32(dc))
                if claimed.contains(neighbour) { return true }
                if let when = mine[neighbour], index - when > selfClaimGapCells { return true }
            }
        }
        return false
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
