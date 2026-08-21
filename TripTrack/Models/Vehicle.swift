import Foundation
import SwiftUI

struct Vehicle: Identifiable, Codable {
    let id: UUID
    var name: String
    /// Carries the COLOUR, and stays a name every shipped build can draw.
    var avatarEmoji: String
    /// Carries the SILHOUETTE. Separate from `avatarEmoji` so that a build
    /// which has never heard of this style still renders a car — see
    /// `VehicleAvatar`.
    var avatarStyle: String
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
         avatarStyle: String = VehicleAvatar.defaultStyle,
         type: VehicleType = .car, plate: String = "", plateVisible: Bool = false,
         visibleToOthers: Bool = true,
         odometerKm: Double = 0, level: Int = 1, stickers: [VehicleSticker] = [],
         createdAt: Date = Date(),
         cityConsumption: Double = 10.0, highwayConsumption: Double = 6.0,
         fuelPrice: Double = 56.0, fuelCurrency: String = FuelCurrency.current) {
        self.id = id
        self.name = name
        self.avatarEmoji = avatarEmoji
        self.avatarStyle = avatarStyle
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
        // Absent from every payload written before the silhouette became its
        // own axis, and absent from any server that has not shipped the column
        // — both mean «a car», which is what those vehicles always were.
        avatarStyle = try c.decodeIfPresent(String.self, forKey: .avatarStyle)
            ?? VehicleAvatar.defaultStyle
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
    /// Composed from the two axes rather than listed by hand: a hand-written
    /// matrix of silhouettes times colours drifts the moment a sprite is added
    /// on one side and forgotten on the other.
    static let pixelCarAssets = VehicleAvatar.allAssets

    /// Emoji avatars are no longer offered, but vehicles created before the
    /// switch still carry one and must keep rendering.
    static let legacyEmojiAvatars = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🏁", "🗺️", "⛽"]

    var isPixelAvatar: Bool {
        VehicleAvatar.isAsset(avatarEmoji)
    }

    /// Emoji for inline text display — a car glyph stands in for pixel-car avatars
    /// (whose `avatarEmoji` holds an asset name, not an emoji).
    var displayEmoji: String {
        isPixelAvatar ? VehicleAvatar.textFallback : avatarEmoji
    }

    var avatarImageName: String? {
        // Resolved against the type rather than trusted as stored: a payload
        // can arrive with a saloon on a bicycle — from an older client, or
        // from a type that was changed on another device — and drawing that
        // pair faithfully would just show the bug to the user.
        let style = VehicleAvatar.resolveStyle(avatarStyle, forType: type.rawValue)
        return VehicleAvatar.assetName(style: style, avatar: avatarEmoji)
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
                // Nearest-neighbour, and after `resizable()` — `resizable()`
                // rebuilds the Image, so a hint set before it is not
                // guaranteed to survive. This was the only pixel-art call
                // site in the app missing it, which left the owner's own car
                // the one blurry sprite on screen: 44 pt in the garage row,
                // 30 pt in the profile and 64 pt on the vehicle detail.
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(avatarEmoji)
                .font(.system(size: size * 0.6))
        }
    }
}
