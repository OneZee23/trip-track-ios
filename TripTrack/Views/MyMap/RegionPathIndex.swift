import MapKit

/// Контур административной единицы — ровно то, что нужно кисти тумана, и
/// ничего больше.
///
/// Отдельный тип, а не `RegionAtlas.Region`, по двум причинам. Первая: кисти
/// нужны только кольца и ответ «страна или регион», а не имена, центроиды и
/// коды; вторая — страны приезжают в атлас Задачей 1, и индекс обязан
/// собираться и до её слияния, просто без них.
struct RegionOutline {
    let id: String
    /// Страна рисуется толще и живёт на дальнем уровне; регион — тоньше и
    /// только на среднем.
    let isCountry: Bool
    /// Плоские кольца `[lat, lon, lat, lon, …]` — в том же виде, в каком их
    /// держит `RegionAtlas`: на 35 000 вершин это разница между одним массивом
    /// и 35 000 структур.
    let rings: [[Double]]
}

extension RegionOutline {
    /// Контуры стран — у ВСЕХ стран мира: на дальнем уровне мир делят именно
    /// они. Страна без колец (микрогосударство, чьё кольцо не прошло порог
    /// сборки бандла) отбрасывается здесь: у неё есть центр ради подписи, но
    /// обводить нечего.
    ///
    /// Регионов здесь больше НЕТ. Их геометрия нужна была заливке
    /// посещённого, а заливка ушла; подписи берут центроид и рамку прямо из
    /// атласа, путей им не надо.
    static func countries(from atlas: RegionAtlas) -> [RegionOutline] {
        atlas.countries.compactMap { country in
            country.rings.isEmpty
                ? nil
                : RegionOutline(id: country.id, isCountry: true, rings: country.rings)
        }
    }

    static func all(from atlas: RegionAtlas) -> [RegionOutline] { countries(from: atlas) }
}

/// Готовые контуры этого куска мира. Только страны: заливки посещённых
/// регионов и контуры их границ были и ушли с «ночной картой» 17 сентября —
/// под ними пропадала сама карта.
struct RegionPaths {
    var countryBorders: [CGPath] = []

    var isEmpty: Bool { countryBorders.isEmpty }
}

/// Границы регионов и стран в `CGPath`, собранные ОДИН раз и вне главного
/// потока, — по образцу `MapPathIndex` и по той же причине.
///
/// Складывать `CGPath` из 35 000 вершин в `draw` нельзя: MapKit зовёт его на
/// своих потоках отрисовки, по тайлу на поток, и первый же тайл собирал бы
/// весь атлас, а остальные ждали бы его на замке. Поэтому сборка — на фоновой
/// очереди, а до готовности кисть рисует туман БЕЗ границ. Именно без границ,
/// а не сплошной заливкой: туман и так непрозрачен, и отсутствие линий — это
/// честный промежуточный кадр, а не дыра в карту Apple.
///
/// Индекс ОДИН на приложение: география не меняется ни от слоя открытого, ни
/// от экрана, и второй экземпляр значил бы вторую сборку тех же путей.
final class RegionPathIndex {
    static let shared = RegionPathIndex()

    /// Уровень, на котором контуры вообще рисуются, — ровно один: `.far`.
    ///
    /// Ближе границы показывает сама карта Apple, и с «ночной картой» она
    /// видна сквозь мглу: вторая линия рядом с её собственной была бы просто
    /// вторым контуром. На `.far` карта Apple свои границы уже не рисует, а
    /// делить мир чем-то надо.
    static func draws(countries lod: RevealedLayer.LOD) -> Bool { lod == .far }

    /// Через сколько вершин брать по одной. На дальнем уровне контур страны
    /// шириной в полтора экранных пикселя не стоит своих тысяч вершин; на
    /// среднем регион уже занимает полэкрана, и прореживание было бы видно
    /// углами.
    static func stride(for lod: RevealedLayer.LOD) -> Int {
        switch lod {
        case .fine: return 1
        case .mid:  return 1
        case .far:  return 3
        }
    }

    private struct Entry {
        let id: String
        let isCountry: Bool
        let box: MKMapRect
        let path: CGPath
        let vertices: Int
    }

    /// Читают потоки отрисовки, пишет фоновый — тот же замок и та же причина,
    /// что у `MapPathIndex`.
    private let lock = NSLock()
    private var built: [RevealedLayer.LOD: [Entry]] = [:]
    private var didBuild = false
    private var preparing = false

    init() {}

    /// Собран ли индекс.
    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return didBuild
    }

    /// Сколько вершин легло в этот уровень — единица счёта для сторожа
    /// прореживания.
    func vertexCount(for lod: RevealedLayer.LOD) -> Int {
        lock.lock(); defer { lock.unlock() }
        return built[lod]?.reduce(0) { $0 + $1.vertices } ?? 0
    }

    /// Собрать в фоне, если ещё не собрано. Идемпотентно и безопасно звать
    /// откуда угодно: её зовут и вью-модель «Атласа» на старте, и оба
    /// рисовальщика лениво.
    ///
    /// Атлас не загружен — НИЧЕГО не защёлкивается: пустая выборка не есть
    /// работа (та же ловушка, что у `rebuildIfNeeded` слоя открытого), и
    /// следующий зов соберёт всё честно.
    func prepareIfNeeded(atlas: RegionAtlas = .shared) {
        guard atlas.isLoaded else { return }
        lock.lock()
        guard !didBuild, !preparing else { lock.unlock(); return }
        preparing = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.prepare(outlines: RegionOutline.all(from: atlas))
        }
    }

    /// Собрать прямо здесь. Зовут её постер (он и так в фоне и рисуется один
    /// раз) и тест.
    func prepare(
        outlines: [RegionOutline],
        transform: @escaping (MKMapPoint) -> CGPoint = { CGPoint(x: $0.x, y: $0.y) }
    ) {
        var made: [RevealedLayer.LOD: [Entry]] = [:]
        for lod in RevealedLayer.LOD.allCases {
            guard Self.draws(countries: lod) else { continue }
            let step = Self.stride(for: lod)
            var entries: [Entry] = []
            for outline in outlines where outline.isCountry {
                if let entry = Self.entry(for: outline, step: step, transform: transform) {
                    entries.append(entry)
                }
            }
            made[lod] = entries
        }
        lock.lock()
        built = made
        didBuild = true
        preparing = false
        lock.unlock()
    }

    /// Контуры, задевающие `rect`. `nil` — «индекс ещё не собран» или «на
    /// этом уровне контуров не рисуют вовсе»; и то и другое значит для кисти
    /// одно: рисовать мглу без них.
    func paths(in rect: MKMapRect, lod: RevealedLayer.LOD) -> RegionPaths? {
        lock.lock()
        let entries = built[lod]
        lock.unlock()
        guard let entries, !entries.isEmpty else { return nil }

        var out = RegionPaths()
        for entry in entries where entry.box.intersects(rect) {
            out.countryBorders.append(entry.path)
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Геометрия

    private static func entry(
        for outline: RegionOutline, step: Int, transform: (MKMapPoint) -> CGPoint
    ) -> Entry? {
        let path = CGMutablePath()
        var box = MKMapRect.null
        var vertices = 0
        for ring in outline.rings {
            let count = ring.count / 2
            guard count > 2 else { continue }
            // Кольцо через антимеридиан в плоском Меркаторе не выражается
            // вовсе: точки по обе стороны от 180° разъезжаются на полмира, и
            // контур Чукотки лёг бы полосой через весь глобус. Такое кольцо
            // просто не рисуется — границы у него нет, а карта цела.
            var minLon = Double.greatestFiniteMagnitude
            var maxLon = -Double.greatestFiniteMagnitude
            for i in 0..<count {
                minLon = Swift.min(minLon, ring[2 * i + 1])
                maxLon = Swift.max(maxLon, ring[2 * i + 1])
            }
            guard maxLon - minLon < 180 else { continue }

            // Шаг зажимается по длине кольца: контур в четыре вершины
            // (прямоугольная страна, островок) прореживанием превращается в
            // отрезок, и граница у него пропадает вовсе.
            let effective = Swift.max(1, Swift.min(step, count / 4))
            var indices = Swift.stride(from: 0, to: count, by: effective).map { $0 }
            // Последняя вершина обязана остаться: без неё прореженный контур
            // замыкается не туда, где кончался исходный.
            if indices.last != count - 1 { indices.append(count - 1) }
            guard indices.count > 2 else { continue }

            for (offset, i) in indices.enumerated() {
                let point = MKMapPoint(CLLocationCoordinate2D(
                    latitude: ring[2 * i], longitude: ring[2 * i + 1]))
                box = box.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                let converted = transform(point)
                if offset == 0 { path.move(to: converted) } else { path.addLine(to: converted) }
            }
            path.closeSubpath()
            vertices += indices.count
        }
        guard vertices > 0, !box.isNull else { return nil }
        return Entry(id: outline.id, isCountry: outline.isCountry,
                     box: box, path: path, vertices: vertices)
    }
}
