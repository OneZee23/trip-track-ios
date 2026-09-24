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
    /// В простое — прежние 100 м: простой это слайдер старта, а он в 0.8.2.
    static let idleAccuracyLimit: Double = 100
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
