import Foundation

struct VehicleSyncPayload: Codable {
    let id: UUID
    let name: String
    let avatarEmoji: String
    let odometerKm: Double
    let level: Int
    let stickersJson: String?
    let cityConsumption: Double
    let highwayConsumption: Double
    let fuelPrice: Double
    let conflictVersion: Int
    let lastModifiedAt: Date
    /// Added after the garage learned about transport other than cars. Optional
    /// on the way in: a server that has not shipped these columns yet simply
    /// omits them, and the vehicle decodes as a plated car, which is what every
    /// vehicle written before this was.
    let vehicleType: String?
    /// The silhouette. Optional for the same reason the fields above are: a
    /// server without the column omits it and the vehicle decodes as a car,
    /// which every vehicle written before this was. Deliberately NOT folded
    /// into `avatarEmoji` — that string has to stay drawable by builds that
    /// shipped before this style existed. See `VehicleAvatar`.
    let avatarStyle: String?
    let plate: String?
    /// The server is the one that must honour this. When false the plate has to
    /// be withheld from public responses at the source — a client-side blank is
    /// not privacy, it is a blindfold on one of the readers.
    let plateVisible: Bool?
    let visibleToOthers: Bool?
    let fuelCurrency: String?

    init(
        id: UUID,
        name: String,
        avatarEmoji: String,
        odometerKm: Double,
        level: Int,
        stickersJson: String?,
        cityConsumption: Double,
        highwayConsumption: Double,
        fuelPrice: Double,
        conflictVersion: Int,
        lastModifiedAt: Date,
        vehicleType: String? = nil,
        avatarStyle: String? = nil,
        plate: String? = nil,
        plateVisible: Bool? = nil,
        visibleToOthers: Bool? = nil,
        fuelCurrency: String? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarEmoji = avatarEmoji
        self.odometerKm = odometerKm
        self.level = level
        self.stickersJson = stickersJson
        self.cityConsumption = cityConsumption
        self.highwayConsumption = highwayConsumption
        self.fuelPrice = fuelPrice
        self.conflictVersion = conflictVersion
        self.lastModifiedAt = lastModifiedAt
        self.vehicleType = vehicleType
        self.avatarStyle = avatarStyle
        self.plate = plate
        self.plateVisible = plateVisible
        self.visibleToOthers = visibleToOthers
        self.fuelCurrency = fuelCurrency
    }
}
