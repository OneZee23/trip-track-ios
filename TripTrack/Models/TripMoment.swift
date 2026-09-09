import Foundation

/// Один узел ленты «Моменты» на экране поездки.
///
/// Лента отвечает на вопрос «как прошла дорога» по порядку: старт, отметки,
/// снимки, финиш. Отметка — то, что человек поставил сам (или геокодер
/// назвал). Стопка снимков — кадры, которые никакой отметке не достались, но
/// встали на маршрут по координате или по времени съёмки: место без имени,
/// которое одним нажатием становится отметкой.
enum TripMoment: Identifiable {
    case checkpoint(TripCheckpoint, number: Int, photos: [TripPhoto])
    case photos(fix: TripRouteLocator.Fix, photos: [TripPhoto])

    var id: UUID {
        switch self {
        case .checkpoint(let checkpoint, _, _): return checkpoint.id
        case .photos(_, let photos): return photos[0].id
        }
    }

    var elapsedFromStart: TimeInterval {
        switch self {
        case .checkpoint(let checkpoint, _, _): return checkpoint.elapsedFromStart
        case .photos(let fix, _): return fix.elapsedFromStart
        }
    }

    var distanceFromStart: Double {
        switch self {
        case .checkpoint(let checkpoint, _, _): return checkpoint.distanceFromStart
        case .photos(let fix, _): return fix.distanceFromStart
        }
    }
}

enum TripMoments {
    /// Снимок без отметки и место на маршруте, куда он встал.
    struct PlacedPhoto {
        let photo: TripPhoto
        let fix: TripRouteLocator.Fix
    }

    /// Собирает ленту: отметки нумеруются по порядку во времени, свободные
    /// снимки складываются в стопки — новая стопка начинается, когда от первого
    /// кадра прошло больше `gap`. То же окно, что связывает снимок с отметкой:
    /// «рядом» для ленты и для отметки должно значить одно и то же.
    static func build(
        checkpoints: [TripCheckpoint],
        links: [UUID: [TripPhoto]],
        loose: [PlacedPhoto],
        gap: TimeInterval = TripCheckpointPhotos.timeWindow
    ) -> [TripMoment] {
        var moments: [TripMoment] = checkpoints
            .sorted { $0.elapsedFromStart < $1.elapsedFromStart }
            .enumerated()
            .map { .checkpoint($0.element, number: $0.offset + 1, photos: links[$0.element.id] ?? []) }

        var group: [PlacedPhoto] = []
        func flush() {
            guard let first = group.first else { return }
            moments.append(.photos(fix: first.fix, photos: group.map(\.photo)))
            group = []
        }
        for item in loose.sorted(by: { $0.fix.elapsedFromStart < $1.fix.elapsedFromStart }) {
            if let first = group.first, item.fix.elapsedFromStart - first.fix.elapsedFromStart > gap {
                flush()
            }
            group.append(item)
        }
        flush()

        return moments.sorted { $0.elapsedFromStart < $1.elapsedFromStart }
    }
}
