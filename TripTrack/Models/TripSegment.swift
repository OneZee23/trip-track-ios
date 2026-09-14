import Foundation

/// Отрезок между двумя отметками ОДНОЙ поездки: «от заправки до перевала».
///
/// Отметка отвечает на «сколько до этой точки», сегмент — на «сколько между
/// этими двумя»: горный кусок дороги, платный участок, объезд по грунтовке.
/// Вопрос из машины тот же, что породил отметки в 0.6.5, только заданный про
/// середину пути, а не про её начало.
///
/// **Время и километры здесь НЕ хранятся** — и это решение, а не экономия
/// колонок. Обе отметки уже несут `elapsedFromStart` и `distanceFromStart`,
/// посчитанные тем же пятиметровым шагом, что и одометр; хранить разность
/// значило бы завести второй счёт, который однажды разойдётся с первым — ровно
/// та поломка, из-за которой в 0.6.5 километры собрали в `TripDistanceGate`.
/// Считает разность чистая функция при показе.
///
/// **Имя по умолчанию тоже не хранится**, как у отметки: `name == nil` — это
/// «A → B» из имён отметок при показе. Номер и язык телефона меняются, имя в
/// базе — нет.
///
/// **Порядок нормализован при создании**: `fromCheckpointId` — та отметка, что
/// раньше по `elapsedFromStart`. Человек волен выбрать «отрезок до…» и более
/// раннюю отметку — сегмент всё равно направлен по дороге, а не по порядку
/// нажатий.
struct TripSegment: Identifiable, Codable, Equatable {
    let id: UUID
    /// Отметка-начало: раньше по `elapsedFromStart` (см. доккомент типа).
    var fromCheckpointId: UUID
    /// Отметка-конец: позже по `elapsedFromStart`.
    var toCheckpointId: UUID
    /// Имя от человека: «серпантин», «платный участок». `nil` — законно и
    /// обычно: при показе собирается «A → B» из имён отметок.
    var name: String?

    init(id: UUID = UUID(), fromCheckpointId: UUID, toCheckpointId: UUID, name: String? = nil) {
        self.id = id
        self.fromCheckpointId = fromCheckpointId
        self.toCheckpointId = toCheckpointId
        self.name = name
    }
}

/// Время и километры сегмента — считает разность двух отметок, ничего не
/// хранит (см. доккомент `TripSegment`).
enum TripSegmentMetrics {
    /// Обе отметки сегмента, упорядоченные по времени, и разница между ними.
    struct Resolved: Equatable {
        let from: TripCheckpoint
        let to: TripCheckpoint
        let elapsed: TimeInterval
        let metres: Double
    }

    /// `nil` — одной из отметок сегмента нет среди `checkpoints` (например,
    /// её заменил пул с другого телефона). Порядок `from`/`to` — по
    /// `elapsedFromStart` резолвленных отметок, а не по полям сегмента:
    /// хранёный порядок нормализуется при создании, но резолв защищается сам,
    /// разницы всегда ≥ 0.
    static func resolve(_ segment: TripSegment, in checkpoints: [TripCheckpoint]) -> Resolved? {
        guard let a = checkpoints.first(where: { $0.id == segment.fromCheckpointId }),
              let b = checkpoints.first(where: { $0.id == segment.toCheckpointId }) else {
            return nil
        }
        let (from, to) = a.elapsedFromStart <= b.elapsedFromStart ? (a, b) : (b, a)
        return Resolved(
            from: from, to: to,
            elapsed: to.elapsedFromStart - from.elapsedFromStart,
            metres: to.distanceFromStart - from.distanceFromStart)
    }
}

/// Имя сегмента для показа: рукой — побеждает; иначе «A → B» из имён отметок.
enum TripSegmentName {
    /// Имя рукой, иначе «A → B» из имён отметок; безымянная отметка —
    /// «Отметка N» по её номеру во времени среди ВСЕХ отметок поездки — тем
    /// же счётом, что собирает ленту «Моменты» (`TripMoments.build`), чтобы
    /// номер в имени сегмента и номер строки в ленте никогда не разошлись.
    static func text(_ segment: TripSegment, in checkpoints: [TripCheckpoint], lang: LanguageManager.Language) -> String {
        if let name = segment.name, !name.isEmpty { return name }
        guard let resolved = TripSegmentMetrics.resolve(segment, in: checkpoints) else { return "" }
        let sorted = checkpoints.sorted { $0.elapsedFromStart < $1.elapsedFromStart }
        func displayName(_ checkpoint: TripCheckpoint) -> String {
            if let name = checkpoint.name, !name.isEmpty { return name }
            let number = (sorted.firstIndex(where: { $0.id == checkpoint.id }) ?? 0) + 1
            return AppStrings.checkpointDefaultName(lang, number: number)
        }
        return "\(displayName(resolved.from)) → \(displayName(resolved.to))"
    }
}
