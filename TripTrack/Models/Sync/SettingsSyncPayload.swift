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

    // ПЛЮСА ЗДЕСЬ НЕТ, и это решение контракта (0.8.0). `avatarFrame` и
    // `showPlusBadge` живут на АККАУНТЕ, а не в строке настроек: сервер
    // пишет их только через `POST /auth/profile-update` — тем же путём, что
    // `profileBackground`, — и отдаёт обратно в `/auth/me`. Второй писатель
    // в этом проводе означал бы, что рамку меняют два запроса, порядок
    // которых никто не гарантирует; держит `SettingsSyncPayloadTests`.

    /// Явный инициализатор оставлен от версии, где у пейлоада были поля с
    /// умолчаниями: старые прямые вызовы (`RemoteSettingsMergeTests`,
    /// `SettingsUnitWireTests`) передают ровно эти аргументы позиционно.
    init(
        id: UUID, avatarEmoji: String, themeMode: String, language: String,
        distanceUnit: String, volumeUnit: String, fuelConsumption: Double,
        fuelPrice: Double, fuelCurrency: String, selectedVehicleId: UUID?,
        profileLevel: Int, profileXp: Int, currentStreak: Int, bestStreak: Int,
        lastTripDate: Date?, conflictVersion: Int, lastModifiedAt: Date
    ) {
        self.id = id
        self.avatarEmoji = avatarEmoji
        self.themeMode = themeMode
        self.language = language
        self.distanceUnit = distanceUnit
        self.volumeUnit = volumeUnit
        self.fuelConsumption = fuelConsumption
        self.fuelPrice = fuelPrice
        self.fuelCurrency = fuelCurrency
        self.selectedVehicleId = selectedVehicleId
        self.profileLevel = profileLevel
        self.profileXp = profileXp
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.lastTripDate = lastTripDate
        self.conflictVersion = conflictVersion
        self.lastModifiedAt = lastModifiedAt
    }
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
        // Разбито на именованные константы, а не одно выражение из
        // семнадцати аргументов: компилятор переставал укладываться в
        // отведённое время на типизацию цельного вызова — тот же предел,
        // что у `TripDetailView.body`.
        let themeMode: String = entity.themeMode ?? "dark"
        let language: String = entity.language ?? "ru"
        let distanceUnit: String = entity.distanceUnit ?? settings.distanceUnit.rawValue
        let volumeUnit: String = entity.volumeUnit ?? settings.volumeUnit.rawValue
        let fuelCurrency: String = entity.fuelCurrency ?? "€"
        let lastModifiedAt: Date = entity.lastModifiedAt ?? Date()
        self.init(
            id: settings.localUserId,
            avatarEmoji: settings.avatarEmoji,
            themeMode: themeMode,
            language: language,
            distanceUnit: distanceUnit,
            volumeUnit: volumeUnit,
            fuelConsumption: entity.fuelConsumption,
            fuelPrice: entity.fuelPrice,
            fuelCurrency: fuelCurrency,
            selectedVehicleId: settings.selectedVehicleId,
            profileLevel: Int(entity.profileLevel),
            profileXp: Int(entity.profileXP),
            currentStreak: Int(entity.currentStreak),
            bestStreak: Int(entity.bestStreak),
            lastTripDate: entity.lastTripDate,
            conflictVersion: Int(entity.conflictVersion),
            lastModifiedAt: lastModifiedAt
        )
    }
}
