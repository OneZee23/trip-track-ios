import Foundation
import SwiftUI

struct Vehicle: Identifiable {
    let id: UUID
    var name: String
    var avatarEmoji: String
    var odometerKm: Double
    var level: Int
    var stickers: [VehicleSticker]
    var createdAt: Date
    var cityConsumption: Double   // L/100km (or equivalent)
    var highwayConsumption: Double
    var fuelPrice: Double          // per liter/gallon

    init(id: UUID = UUID(), name: String = "", avatarEmoji: String = "🏎️",
         odometerKm: Double = 0, level: Int = 1, stickers: [VehicleSticker] = [],
         createdAt: Date = Date(),
         cityConsumption: Double = 10.0, highwayConsumption: Double = 6.0,
         fuelPrice: Double = 56.0) {
        self.id = id
        self.name = name
        self.avatarEmoji = avatarEmoji
        self.odometerKm = odometerKm
        self.level = level
        self.stickers = stickers
        self.createdAt = createdAt
        self.cityConsumption = cityConsumption
        self.highwayConsumption = highwayConsumption
        self.fuelPrice = fuelPrice
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

    static let defaultAvatars = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🏁", "🗺️", "⛽"]

    // Pixel car assets — exclusive to default "Телега" vehicle, not selectable by user
    static let pixelCarAssets = [
        "pixel_car_orange", "pixel_car_green", "pixel_car_black",
        "pixel_car_gray", "pixel_car_blue", "pixel_car_red"
    ]

    var isPixelAvatar: Bool {
        avatarEmoji.hasPrefix("pixel_car_")
    }

    var avatarImageName: String? {
        isPixelAvatar ? avatarEmoji : nil
    }

    var levelTitle: String {
        VehicleLevelSystem.title(level: level, lang: .en)
    }

    func levelTitle(_ lang: LanguageManager.Language) -> String {
        VehicleLevelSystem.title(level: level, lang: lang)
    }

    var progressToNextLevel: Double {
        VehicleLevelSystem.progressToNext(km: odometerKm, level: level)
    }

    var kmToNextLevel: Double? {
        guard level < VehicleLevelSystem.maxLevel else { return nil }
        return VehicleLevelSystem.kmForNextLevel(level) - odometerKm
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
