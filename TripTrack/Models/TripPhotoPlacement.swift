import Foundation
import CoreLocation

/// Где на маршруте стоит фотография.
///
/// Три источника по убыванию доверия, и порядок здесь — самое важное, что есть
/// в этом файле:
///
/// 1. **Координата в самом снимке.** Правда о том, где стояла камера. Точнее
///    любого вычисления, поэтому спрашивается первой.
/// 2. **Время съёмки и трек.** Геометки выключены у многих, а кадр из
///    мессенджера теряет их всегда — тогда место считается по треку. С 0.6.5
///    это стало точным: раньше точки лежали в пяти метрах, а на медленном ходу
///    в трёх с половиной секундах друг от друга, и ответ был бы «примерно
///    где-то в этом квартале».
/// 3. **Ничего.** Снимок остаётся в галерее без метки на карте.
///
/// Третий пункт — не недоделка. У снимков, добавленных до 0.6.5, времени
/// съёмки нет: тогда сохранялось только время попадания в базу, а оно может
/// отличаться на дни. Поставить кадр по нему значило бы увезти его за сотню
/// километров от места съёмки, и это хуже, чем не ставить вовсе.
enum TripPhotoPlacement {

    struct Prepared {
        let links: [UUID: [TripPhoto]]
        let placed: [Placed]
        let fixes: [UUID: TripRouteLocator.Fix]
    }

    /// Value work only; callers hand in a single trip snapshot. Pins and the
    /// moments list share each reading instead of walking the track twice.
    static func prepare(
        photos: [TripPhoto], checkpoints: [TripCheckpoint],
        points: [TrackPoint], startDate: Date
    ) throws -> Prepared {
        try Task.checkCancellation()
        let links = TripCheckpointPhotos.link(checkpoints: checkpoints, photos: photos, points: points)
        let attached = Set(links.values.flatMap { $0 }.map(\.id))
        let placed = place(photos, on: points).filter { !attached.contains($0.id) }
        guard !placed.isEmpty else { return Prepared(links: links, placed: [], fixes: [:]) }

        try Task.checkCancellation()
        let index = TripRouteLocator.Index(points: points, startDate: startDate)
        let photosByID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var fixes: [UUID: TripRouteLocator.Fix] = [:]
        for item in placed {
            try Task.checkCancellation()
            if let photo = photosByID[item.id], let fix = index.fix(for: photo) {
                fixes[item.id] = fix
            }
        }
        return Prepared(links: links, placed: placed, fixes: fixes)
    }

    /// Cancellation follows the screen's rebuild task into the worker. No
    /// managed object, image loading or UI state crosses this boundary.
    static func prepareAsync(
        photos: [TripPhoto], checkpoints: [TripCheckpoint],
        points: [TrackPoint], startDate: Date
    ) async throws -> Prepared {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try prepare(photos: photos, checkpoints: checkpoints, points: points, startDate: startDate)
        }
        let prepared = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return prepared
    }

    struct Placed: Identifiable, Equatable {
        let id: UUID
        let filename: String
        let latitude: Double
        let longitude: Double
        /// Откуда взялось место — для отладки и для будущего пересчёта.
        let source: Source

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        enum Source: String, Equatable {
            /// Координата из самого снимка.
            case photo
            /// Вычислено по времени съёмки и треку.
            case track
        }
    }

    /// Расставить снимки поездки по её маршруту.
    static func place(_ photos: [TripPhoto], on points: [TrackPoint]) -> [Placed] {
        guard !photos.isEmpty else { return [] }

        return photos.compactMap { photo in
            if let coordinate = photo.exifCoordinate {
                return Placed(id: photo.id, filename: photo.filename,
                              latitude: coordinate.latitude, longitude: coordinate.longitude,
                              source: .photo)
            }
            guard let capturedAt = photo.capturedAt,
                  !points.isEmpty,
                  let first = points.first, let last = points.last,
                  capturedAt >= first.timestamp, capturedAt <= last.timestamp
            else { return nil }

            var low = 0
            var high = points.count - 1
            while low < high {
                let mid = (low + high) / 2
                if points[mid].timestamp < capturedAt { low = mid + 1 } else { high = mid }
            }
            var index = low
            if index > 0 {
                let before = capturedAt.timeIntervalSince(points[index - 1].timestamp)
                let after = points[index].timestamp.timeIntervalSince(capturedAt)
                if before < after { index -= 1 }
            }
            let point = points[index]
            return Placed(id: photo.id, filename: photo.filename,
                          latitude: point.latitude, longitude: point.longitude,
                          source: .track)
        }
    }
}
