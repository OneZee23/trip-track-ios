import Foundation

/// Решение о сыром фиксе CoreLocation — одно на провайдер и на стенд
/// (спека §2.1). Чистая функция: две копии правила «какой фикс годится»
/// разошлись бы молча.
enum FixGate {
    enum Reason: String, Equatable {
        case invalid
        case accuracy
        case stale
        case speed
    }

    enum Decision: Equatable {
        case accept
        case reject(Reason)
    }

    /// Потолок точности на записи. Число стартовое, а не выстраданное: выше
    /// начинается позиция по вышкам и Wi-Fi, у которой нет формы дороги.
    /// Подбирается на стенде (`TrackReplayTests`), и причина нового числа
    /// пишется здесь же. Одометр своих 65 м не меняет —
    /// `TripDistanceGate.odometerAccuracyLimit`.
    static let recordingAccuracyLimit: Double = 200
    /// В простое — ТОТ ЖЕ потолок, что на записи (0.8.3).
    ///
    /// Было 100 м, и это число не выбирали — его отложили: «простой это
    /// слайдер старта, а он в 0.8.2» (спека 0.8.1 §2.1). Очередь дошла.
    ///
    /// **Отдельный, более строгий потолок в простое не покупал ничего.** Фикс,
    /// принятый в простое, тут же пересматривается потолком записи, как только
    /// запись началась, а в километры он не идёт ни при каком потолке —
    /// одометр отбирает точки своей дверью (`TripDistanceGate
    /// .odometerAccuracyLimit`, 65 м). То есть строгость в простое не улучшала
    /// ни трек, ни пробег: она только дольше держала человека перед
    /// заблокированным слайдером под плохим небом — во дворе, в подземном
    /// паркинге, между высотками. Ровно это и есть репорт «не могу передвинуть
    /// слайдер, чтобы начать запись».
    ///
    /// Потребителей у фикса в простое ровно три, и ни одному 150 м не мешают:
    /// слайдер («знаем ли мы вообще, где находимся»), значок качества сигнала
    /// (на 150 м он честно скажет «GPS слабый» вместо вечного «Ищем
    /// спутники») и камера карты. Автотрекинг сюда не ходит:
    /// `updateMovementForInactivity` выходит первой строкой, пока записи нет.
    ///
    /// Меняешь — меняй вместе с потолком записи: разойдясь, они дают простой
    /// строже записи, а это состояние, в котором начать запись нельзя, хотя
    /// записывать уже было бы можно. Держит `FixGateTests`.
    static let idleAccuracyLimit: Double = recordingAccuracyLimit
    static let maxLocationAge: TimeInterval = 10
    /// ~300 км/ч.
    static let maxSpeedMS: Double = 83.3

    static func decide(
        horizontalAccuracy: Double,
        ageSeconds: TimeInterval,
        speedMS: Double,
        isRecording: Bool,
        recordingLimit: Double = recordingAccuracyLimit
    ) -> Decision {
        guard horizontalAccuracy >= 0 else { return .reject(.invalid) }
        let limit = isRecording ? recordingLimit : idleAccuracyLimit
        guard horizontalAccuracy <= limit else { return .reject(.accuracy) }
        guard ageSeconds < maxLocationAge else { return .reject(.stale) }
        // Фикс с неизвестной скоростью (−1) оставляем: скорость нужна только
        // фильтру дрейфа, а тот неизвестную не читает.
        if max(0, speedMS) > maxSpeedMS { return .reject(.speed) }
        return .accept
    }
}
