import Foundation
import CoreData
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var avatarEmoji: String = "😎"
    @Published var themeMode: String = "dark"
    @Published var language: String = "ru"
    @Published var fuelConsumption: Double = 7.8
    @Published var fuelPrice: Double = 56.0
    @Published var selectedVehicleId: UUID?
    @Published var vehicles: [Vehicle] = []

    // Gamification
    @Published var profileXP: Int = 0
    @Published var profileLevel: Int = 1
    @Published var currentStreak: Int = 0
    @Published var bestStreak: Int = 0

    private let persistenceController: PersistenceController
    private var settingsEntity: UserSettingsEntity?

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        loadSettings()
        loadVehicles()
    }

    // MARK: - Settings

    private func loadSettings() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        request.fetchLimit = 1

        if let entity = try? context.fetch(request).first {
            settingsEntity = entity
            syncFromEntity(entity)
        } else {
            let entity = UserSettingsEntity(context: context)
            entity.id = UUID()
            persistenceController.save()
            settingsEntity = entity
            syncFromEntity(entity)
        }
    }

    private static let vehicleEmojis: Set<String> = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🚐", "🏁", "⛽"]

    private func syncFromEntity(_ entity: UserSettingsEntity) {
        let stored = entity.avatarEmoji ?? "😎"
        // Migrate: old vehicle emoji as profile avatar → reset to person emoji
        avatarEmoji = Self.vehicleEmojis.contains(stored) ? "😎" : stored
        themeMode = entity.themeMode ?? "dark"
        language = entity.language ?? "ru"
        fuelConsumption = entity.fuelConsumption
        fuelPrice = entity.fuelPrice
        selectedVehicleId = entity.selectedVehicleId
        // Gamification
        profileXP = Int(entity.profileXP)
        profileLevel = Int(entity.profileLevel)
        currentStreak = Int(entity.currentStreak)
        bestStreak = Int(entity.bestStreak)
    }

    func saveSettings() {
        guard let entity = settingsEntity else { return }
        entity.avatarEmoji = avatarEmoji
        entity.themeMode = themeMode
        entity.language = language
        entity.fuelConsumption = fuelConsumption
        entity.fuelPrice = fuelPrice
        entity.selectedVehicleId = selectedVehicleId
        persistenceController.save()
    }

    // MARK: - Vehicles

    private func loadVehicles() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VehicleEntity.name, ascending: true)]

        vehicles = (try? context.fetch(request))?.compactMap { vehicleFromEntity($0) } ?? []
    }

    func addVehicle(name: String, emoji: String) {
        let context = persistenceController.container.viewContext
        let entity = VehicleEntity(context: context)
        entity.id = UUID()
        entity.name = name
        entity.avatarEmoji = emoji
        entity.odometerKm = 0
        entity.vehicleLevel = 1
        entity.createdAt = Date()
        persistenceController.save()
        loadVehicles()
    }

    func deleteVehicle(id: UUID) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let entity = try? context.fetch(request).first {
            context.delete(entity)
            persistenceController.save()
            loadVehicles()
        }
    }

    private func vehicleFromEntity(_ entity: VehicleEntity) -> Vehicle? {
        guard let id = entity.id else { return nil }

        // Decode stickers from JSON
        var stickers: [VehicleSticker] = []
        if let json = entity.stickersJSON, !json.isEmpty,
           let data = json.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            stickers = ids.compactMap { VehicleSticker(rawValue: $0) }
        }

        return Vehicle(
            id: id,
            name: entity.name ?? "",
            avatarEmoji: entity.avatarEmoji ?? "🏎️",
            odometerKm: entity.odometerKm,
            level: Int(entity.vehicleLevel),
            stickers: stickers,
            createdAt: entity.createdAt ?? Date(),
            cityConsumption: entity.cityConsumption,
            highwayConsumption: entity.highwayConsumption,
            fuelPrice: entity.fuelPrice
        )
    }

    func renameVehicle(id: UUID, name: String) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.name = name
            persistenceController.save()
            loadVehicles()
        }
    }

    func updateVehicleFuel(id: UUID, city: Double, highway: Double, price: Double) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.cityConsumption = city
            entity.highwayConsumption = highway
            entity.fuelPrice = price
            persistenceController.save()
            loadVehicles()
        }
    }

    func reloadGamificationState() {
        if let entity = settingsEntity {
            profileXP = Int(entity.profileXP)
            profileLevel = Int(entity.profileLevel)
            currentStreak = Int(entity.currentStreak)
            bestStreak = Int(entity.bestStreak)
        }
        loadVehicles()
    }
}
