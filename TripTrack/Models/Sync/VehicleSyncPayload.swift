import Foundation

struct VehicleSyncPayload: Codable {
    let id: UUID
    let name: String
    let avatarEmoji: String
    let odometerKm: Double
    /// Пробег с приборки. Опционально: старый сервер ключа не знает.
    ///
    /// Кодируется ВСЕГДА, даже как `null`. `encodeIfPresent` выбрасывал бы
    /// очистку — сервер оставлял бы старое число, а следующий пул возвращал бы
    /// его поверх локальной очистки. То есть стереть пробег было невозможно.
    var manualOdometerKm: Double?
    /// Пришёл ли ключ в ответе сервера. Отличает «сервер не знает про поле»
    /// (не трогать локальное) от «сервер прислал null» (очистить).
    /// `decodeIfPresent` эти два случая не различает, `contains` — различает.
    var manualOdometerKnown: Bool = false
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
        manualOdometerKm: Double? = nil,
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
        self.manualOdometerKm = manualOdometerKm
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

    // MARK: - Codable вручную

    /// Ручной кодинг существует ради ОДНОГО поля — `manualOdometerKm`.
    ///
    /// Синтезированный вариант шлёт его через `encodeIfPresent`, то есть
    /// выбрасывает `nil`. Для этого поля `nil` — не «нечего слать», а
    /// «человек стёр значение»: без явного `null` сервер оставлял бы старое
    /// число, а следующий пул возвращал бы его поверх локальной очистки, и
    /// стереть пробег было бы невозможно в принципе.
    ///
    /// На чтении та же граница с другой стороны: `contains` отличает «ключа
    /// нет» (сервер про поле не знает — локальное не трогаем) от «пришёл
    /// null» (очистить). `decodeIfPresent` эти случаи не различает.
    enum CodingKeys: String, CodingKey {
        case id, name, avatarEmoji, odometerKm, manualOdometerKm, level
        case stickersJson, cityConsumption, highwayConsumption, fuelPrice
        case conflictVersion, lastModifiedAt, vehicleType, avatarStyle
        case plate, plateVisible, visibleToOthers, fuelCurrency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        avatarEmoji = try c.decode(String.self, forKey: .avatarEmoji)
        odometerKm = try c.decode(Double.self, forKey: .odometerKm)
        manualOdometerKm = try c.decodeIfPresent(Double.self, forKey: .manualOdometerKm)
        manualOdometerKnown = c.contains(.manualOdometerKm)
        level = try c.decode(Int.self, forKey: .level)
        stickersJson = try c.decodeIfPresent(String.self, forKey: .stickersJson)
        cityConsumption = try c.decode(Double.self, forKey: .cityConsumption)
        highwayConsumption = try c.decode(Double.self, forKey: .highwayConsumption)
        fuelPrice = try c.decode(Double.self, forKey: .fuelPrice)
        conflictVersion = try c.decode(Int.self, forKey: .conflictVersion)
        lastModifiedAt = try c.decode(Date.self, forKey: .lastModifiedAt)
        vehicleType = try c.decodeIfPresent(String.self, forKey: .vehicleType)
        avatarStyle = try c.decodeIfPresent(String.self, forKey: .avatarStyle)
        plate = try c.decodeIfPresent(String.self, forKey: .plate)
        plateVisible = try c.decodeIfPresent(Bool.self, forKey: .plateVisible)
        visibleToOthers = try c.decodeIfPresent(Bool.self, forKey: .visibleToOthers)
        fuelCurrency = try c.decodeIfPresent(String.self, forKey: .fuelCurrency)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(avatarEmoji, forKey: .avatarEmoji)
        try c.encode(odometerKm, forKey: .odometerKm)
        // Именно `encode`, а не `encodeIfPresent` — см. доку выше.
        try c.encode(manualOdometerKm, forKey: .manualOdometerKm)
        try c.encode(level, forKey: .level)
        try c.encodeIfPresent(stickersJson, forKey: .stickersJson)
        try c.encode(cityConsumption, forKey: .cityConsumption)
        try c.encode(highwayConsumption, forKey: .highwayConsumption)
        try c.encode(fuelPrice, forKey: .fuelPrice)
        try c.encode(conflictVersion, forKey: .conflictVersion)
        try c.encode(lastModifiedAt, forKey: .lastModifiedAt)
        try c.encodeIfPresent(vehicleType, forKey: .vehicleType)
        try c.encodeIfPresent(avatarStyle, forKey: .avatarStyle)
        try c.encodeIfPresent(plate, forKey: .plate)
        try c.encodeIfPresent(plateVisible, forKey: .plateVisible)
        try c.encodeIfPresent(visibleToOthers, forKey: .visibleToOthers)
        try c.encodeIfPresent(fuelCurrency, forKey: .fuelCurrency)
    }
}
