import Foundation

struct SettingsSyncPayload: Codable {
    let id: UUID
    let avatarEmoji: String
    let themeMode: String
    let language: String
    let distanceUnit: String
    let volumeUnit: String
    let fuelConsumption: Double
    let fuelPrice: Double
    let fuelCurrency: String
    let selectedVehicleId: UUID?
    let profileLevel: Int
    let profileXp: Int
    let currentStreak: Int
    let bestStreak: Int
    let lastTripDate: Date?
    let conflictVersion: Int
    let lastModifiedAt: Date
}

extension SettingsSyncPayload {
    /// Строка настроек → пейлоад. Отдельным инициализатором, как у поездки
    /// (`TripSyncPayload(entity:)`), ровно за тем, чтобы у провода была
    /// проверяемая середина: `APISyncTransport` собирал пейлоад внутри
    /// приватного метода, который без сети не позвать, и подмена настоящего
    /// выбора на `?? "km"` жила там непроверенной.
    ///
    /// Умолчания здесь — для строки, которую ещё ни разу не сохраняли этой
    /// версией: единицы берутся у `SettingsManager` (то есть у человека), а не
    /// назначаются километрами.
    init(entity: UserSettingsEntity, settings: SettingsManager) {
        self.init(
            id: settings.localUserId,
            avatarEmoji: settings.avatarEmoji,
            themeMode: entity.themeMode ?? "dark",
            language: entity.language ?? "ru",
            distanceUnit: entity.distanceUnit ?? settings.distanceUnit.rawValue,
            volumeUnit: entity.volumeUnit ?? settings.volumeUnit.rawValue,
            fuelConsumption: entity.fuelConsumption,
            fuelPrice: entity.fuelPrice,
            fuelCurrency: entity.fuelCurrency ?? "€",
            selectedVehicleId: settings.selectedVehicleId,
            profileLevel: Int(entity.profileLevel),
            profileXp: Int(entity.profileXP),
            currentStreak: Int(entity.currentStreak),
            bestStreak: Int(entity.bestStreak),
            lastTripDate: entity.lastTripDate,
            conflictVersion: Int(entity.conflictVersion),
            lastModifiedAt: entity.lastModifiedAt ?? Date()
        )
    }
}
