import Foundation
import CoreLocation

/// Какие снимки относятся к какой отметке.
///
/// Отметка и фотография — две записи об одном моменте: остановились у моря,
/// нажали флажок, сняли пару кадров. Связывать их руками — значит просить
/// человека повторить то, что он уже сделал самим фактом съёмки. Поэтому связь
/// выводится, а не хранится: у снимка есть время съёмки и, бывает, координата,
/// у отметки — и то, и другое. Ничего в схеме не меняется, и старые поездки
/// получают связь бесплатно.
///
/// Ручная привязка (`TripCheckpoint.photoId`) остаётся сверху как слово
/// человека: этот кадр — обложка этой отметки, что бы ни говорило время.
enum TripCheckpointPhotos {

    /// Снимок считается «рядом с отметкой», если снят в этом окне от неё.
    /// Пятнадцать минут — потому что остановка у моря длится не минуту, а
    /// кадры делают, погуляв; двадцать пять — это уже обед, и снимки из кафе к
    /// отметке «до моря» отношения не имеют.
    static let timeWindow: TimeInterval = 15 * 60

    /// Для снимков с собственной координатой, но без времени в поездке.
    static let distanceWindow: Double = 300

    /// Отметка → её снимки, обложка первой.
    static func link(
        checkpoints: [TripCheckpoint],
        photos: [TripPhoto],
        points: [TrackPoint]
    ) -> [UUID: [TripPhoto]] {
        guard !checkpoints.isEmpty, !photos.isEmpty else { return [:] }

        var result: [UUID: [TripPhoto]] = [:]
        var taken: Set<UUID> = []

        // 1. Слово человека — сначала: обложка и прикреплённые рукой снимки.
        // Они забираются раньше автоматики, чтобы время съёмки не увело
        // прикреплённый кадр к соседней отметке.
        for checkpoint in checkpoints {
            var manual: [UUID] = []
            if let coverId = checkpoint.photoId { manual.append(coverId) }
            manual.append(contentsOf: checkpoint.photoIds)
            for pid in manual where !taken.contains(pid) {
                guard let photo = photos.first(where: { $0.id == pid }) else { continue }
                result[checkpoint.id, default: []].append(photo)
                taken.insert(pid)
            }
        }

        // 2. Остальные — по времени съёмки, затем по координате кадра.
        for photo in photos where !taken.contains(photo.id) {
            guard let owner = nearestCheckpoint(for: photo, among: checkpoints, points: points) else { continue }
            result[owner.id, default: []].append(photo)
            taken.insert(photo.id)
        }

        // Внутри отметки: обложка, потом прикреплённые в порядке прикрепления,
        // потом остальные по времени съёмки.
        for (id, list) in result {
            guard let checkpoint = checkpoints.first(where: { $0.id == id }) else { continue }
            let rank: (TripPhoto) -> (Int, Int, Date) = { photo in
                if photo.id == checkpoint.photoId { return (0, 0, .distantPast) }
                if let i = checkpoint.photoIds.firstIndex(of: photo.id) { return (1, i, .distantPast) }
                return (2, 0, photo.capturedAt ?? photo.timestamp)
            }
            result[id] = list.sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra.0 != rb.0 { return ra.0 < rb.0 }
                if ra.1 != rb.1 { return ra.1 < rb.1 }
                return ra.2 < rb.2
            }
        }
        return result
    }

    /// Ближайшая по времени отметка в окне; без времени — ближайшая по месту.
    static func nearestCheckpoint(
        for photo: TripPhoto,
        among checkpoints: [TripCheckpoint],
        points: [TrackPoint]
    ) -> TripCheckpoint? {
        if let capturedAt = photo.capturedAt,
           let first = points.first, let last = points.last,
           capturedAt >= first.timestamp.addingTimeInterval(-timeWindow),
           capturedAt <= last.timestamp.addingTimeInterval(timeWindow) {
            let byTime = checkpoints
                .map { ($0, abs($0.timestamp.timeIntervalSince(capturedAt))) }
                .filter { $0.1 <= timeWindow }
                .min { $0.1 < $1.1 }
            if let byTime { return byTime.0 }
        }
        if let coordinate = photo.exifCoordinate {
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let byPlace = checkpoints
                .map { ($0, here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
                .filter { $0.1 <= distanceWindow }
                .min { $0.1 < $1.1 }
            if let byPlace { return byPlace.0 }
        }
        return nil
    }
}
