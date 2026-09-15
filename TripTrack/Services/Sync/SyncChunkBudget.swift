import Foundation

/// Сколько поездок класть в один `/sync/push` — считается в БАЙТАХ JSON, а
/// не в точках трека.
///
/// До 15 сентября 2026 чанк резался «до 25 поездок или 80 000 точек» под
/// серверный лимит тела в 25 МБ. Но лимит у сервера — по РАСПАКОВАННОМУ
/// JSON, а точка трека в нём весит около 280 байт: 80 000 точек — это уже
/// 22 МБ без фотографий и отметок, и поездка на 89 000 точек (79 часов у
/// живого пользователя) не резалась вовсе — сервер отвечал 413, очередь
/// повторяла пять раз, и каждая попытка на 957 МБ без swap клала прод на
/// час-два. Четыре отказа за сутки начались именно так.
///
/// Считать честно, кодируя каждый пейлоад в JSON дважды, дорого: точки
/// кодируются `DateFormatter`-ом по одной. Поэтому — оценка сверху по числу
/// элементов, с запасом (константы проверяет `SyncChunkBudgetTests` против
/// настоящего `JSONEncoder` с тем же форматом дат, что у `APIClient`).
/// Одиночная поездка, которая сама больше бюджета, всё равно уходит одна —
/// резать поездку на части провод не умеет; её судьбу решает серверный лимит
/// (40 МБ с 15 сентября 2026).
enum SyncChunkBudget {
    /// Потолок РАСПАКОВАННОГО JSON одного чанка. 16 МБ при серверном лимите
    /// 40 МБ: запас на то, что оценка — верхняя, и на gzip-буферы сервера.
    static let maxBytes = 16 * 1024 * 1024
    static let maxTrips = 25

    /// Верхние оценки веса элементов в JSON: точка — 36-символьный UUID,
    /// шесть чисел с полной точностью, дата ISO и флаг ≈ 260–290 байт.
    static let bytesPerTrackPoint = 320
    static let bytesPerPhoto = 480
    static let bytesPerCheckpoint = 520
    static let bytesPerSegment = 200
    /// Шапка поездки: заголовок, заметки, превью-полилиния в base64, значки.
    static let baseBytes = 8_192

    static func estimate(trackPoints: Int, photos: Int, checkpoints: Int, segments: Int) -> Int {
        baseBytes
            + trackPoints * bytesPerTrackPoint
            + photos * bytesPerPhoto
            + checkpoints * bytesPerCheckpoint
            + segments * bytesPerSegment
    }

    /// Надо ли отправить накопленный чанк ПЕРЕД тем, как добавить следующую
    /// поездку. Пустой чанк не отправляется никогда — так одиночная поездка
    /// больше бюджета всё равно попадает в свой собственный чанк.
    static func shouldFlush(currentTrips: Int, currentBytes: Int, nextBytes: Int) -> Bool {
        guard currentTrips > 0 else { return false }
        return currentTrips >= maxTrips || currentBytes + nextBytes > maxBytes
    }
}

extension TripSyncPayload {
    /// Оценка веса этой поездки в JSON по `SyncChunkBudget`.
    var estimatedWireBytes: Int {
        SyncChunkBudget.estimate(
            trackPoints: trackPoints?.count ?? 0,
            photos: photos?.count ?? 0,
            checkpoints: checkpoints?.count ?? 0,
            segments: segments?.count ?? 0)
    }
}
