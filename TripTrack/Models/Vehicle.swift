import Foundation
import SwiftUI

struct Vehicle: Identifiable, Codable {
    let id: UUID
    var name: String
    var avatarEmoji: String
    var type: VehicleType
    /// Free text, empty when the owner did not give one — the field is
    /// optional by design. See `VehiclePlate`.
    var plate: String
    /// Whether anyone but the owner may see the plate. Off by default, and
    /// deliberately not derived from `isPublic`: in Russia a plate is enough to
    /// look up the registered owner's name and address, so showing it has to be
    /// a decision someone makes, not a side effect of sharing a trip.
    var plateVisible: Bool
    /// Whether the vehicle itself is shown to anyone else. Off means it does
    /// not appear in the public profile and cannot be named as a companion's
    /// ride; the trips still publish, just without saying what they were made
    /// in. Separate from `plateVisible`, which hides only the number.
    var visibleToOthers: Bool
    var odometerKm: Double
    var level: Int
    var stickers: [VehicleSticker]
    var createdAt: Date
    var cityConsumption: Double   // L/100km (or equivalent)
    var highwayConsumption: Double
    var fuelPrice: Double          // per liter/gallon
    /// Currency symbol for this vehicle's fuel price. Per-vehicle because a
    /// second car can live in a second country; a trip may still override it.
    var fuelCurrency: String

    init(id: UUID = UUID(), name: String = "", avatarEmoji: String = "🏎️",
         type: VehicleType = .car, plate: String = "", plateVisible: Bool = false,
         visibleToOthers: Bool = true,
         odometerKm: Double = 0, level: Int = 1, stickers: [VehicleSticker] = [],
         createdAt: Date = Date(),
         cityConsumption: Double = 10.0, highwayConsumption: Double = 6.0,
         fuelPrice: Double = 56.0, fuelCurrency: String = FuelCurrency.current) {
        self.id = id
        self.name = name
        self.avatarEmoji = avatarEmoji
        self.type = type
        self.plate = plate
        self.plateVisible = plateVisible
        self.visibleToOthers = visibleToOthers
        self.odometerKm = odometerKm
        self.level = level
        self.stickers = stickers
        self.createdAt = createdAt
        self.cityConsumption = cityConsumption
        self.highwayConsumption = highwayConsumption
        self.fuelPrice = fuelPrice
        self.fuelCurrency = fuelCurrency
    }

    /// Decoding tolerates payloads written before these fields existed —
    /// server responses and cached JSON both predate them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        avatarEmoji = try c.decode(String.self, forKey: .avatarEmoji)
        type = try c.decodeIfPresent(VehicleType.self, forKey: .type) ?? .car
        plate = try c.decodeIfPresent(String.self, forKey: .plate) ?? ""
        plateVisible = try c.decodeIfPresent(Bool.self, forKey: .plateVisible) ?? false
        visibleToOthers = try c.decodeIfPresent(Bool.self, forKey: .visibleToOthers) ?? true
        odometerKm = try c.decode(Double.self, forKey: .odometerKm)
        level = try c.decode(Int.self, forKey: .level)
        stickers = try c.decodeIfPresent([VehicleSticker].self, forKey: .stickers) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        cityConsumption = try c.decode(Double.self, forKey: .cityConsumption)
        highwayConsumption = try c.decode(Double.self, forKey: .highwayConsumption)
        fuelPrice = try c.decode(Double.self, forKey: .fuelPrice)
        fuelCurrency = try c.decodeIfPresent(String.self, forKey: .fuelCurrency)
            ?? FuelCurrency.current
    }

    /// Calculate fuel cost for a trip based on speed-weighted city/highway ratio
    func fuelCost(distanceKm: Double, avgSpeedKmh: Double) -> (liters: Double, cost: Double) {
        // Highway ratio: 0% at ≤30 km/h, 100% at ≥80 km/h, linear between
        let highwayRatio = min(1.0, max(0.0, (avgSpeedKmh - 30) / 50))
        let consumption = cityConsumption * (1 - highwayRatio) + highwayConsumption * highwayRatio
        let liters = distanceKm / 100 * consumption
        let cost = liters * fuelPrice
        return (liters, cost)
    }

    /// The avatar set offered in the form: the eight pixel cars the app already
    /// draws on the map and in the poster. They used to be reserved for the
    /// auto-created default vehicle while the picker offered emoji, which meant
    /// the one avatar nobody chose was the only one that matched the app.
    static let pixelCarAssets = [
        "pixel_car_orange", "pixel_car_red", "pixel_car_blue", "pixel_car_green",
        "pixel_car_gray", "pixel_car_black", "pixel_car_white", "pixel_car_silver"
    ]

    /// Emoji avatars are no longer offered, but vehicles created before the
    /// switch still carry one and must keep rendering.
    static let legacyEmojiAvatars = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🏁", "🗺️", "⛽"]

    var isPixelAvatar: Bool {
        avatarEmoji.hasPrefix("pixel_car_")
    }

    /// Emoji for inline text display — a car glyph stands in for pixel-car avatars
    /// (whose `avatarEmoji` holds an asset name, not an emoji).
    var displayEmoji: String {
        isPixelAvatar ? "🚗" : avatarEmoji
    }

    var avatarImageName: String? {
        isPixelAvatar ? avatarEmoji : nil
    }

    // MARK: - Plate

    var hasPlate: Bool {
        type.hasPlate && !plate.isEmpty
    }

    /// What someone *else* is allowed to see. Nil means the plate is not shown
    /// at all — not shown as hidden, not shown as a placeholder. A row reading
    /// «номер скрыт» would still announce that there is something to look for.
    var publicPlate: String? {
        guard visibleToOthers, hasPlate, plateVisible else { return nil }
        return plate
    }

    // MARK: - Level

    var progressToNextLevel: Double {
        VehicleLevelSystem.progressToNext(km: odometerKm, level: level)
    }

    /// Always a number: the ladder has no top rung.
    var kmToNextLevel: Double {
        VehicleLevelSystem.kmToNextLevel(km: odometerKm, level: level)
    }

    var levelColor: Color {
        VehicleLevelSystem.color(for: level)
    }

    @ViewBuilder
    func avatarView(size: CGFloat) -> some View {
        if let imageName = avatarImageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(avatarEmoji)
                .font(.system(size: size * 0.6))
        }
    }
}
