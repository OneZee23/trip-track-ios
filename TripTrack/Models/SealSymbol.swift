import Foundation

/// Что нарисовано внутри печати на «Атласе».
///
/// SF Symbol в 0.7.0 — гравюры придут волной 5 и заменят только картинку, не
/// перечисление: `rawValue` это имя символа, и менять его можно, а вот
/// **имена case'ов — нет**, они уезжают в `DiscoveryEntity.symbol` и в
/// `Riddles.json`.
enum SealSymbol: String, Codable, CaseIterable {
    case pass = "mountain.2", lighthouse = "light.beacon.max", border = "flag.2.crossed",
         ferry = "ferry", dam = "water.waves", bridge = "road.lanes", viewpoint = "binoculars",
         observatory = "telescope", seaRoad = "water.waves.and.arrow.down",
         extreme = "arrow.up.left.and.arrow.down.right",
         centre = "scope", tripoint = "triangle", region = "map", altitude = "mountain.2.fill",
         night = "moon.stars", country = "globe", generic = "seal"
}
