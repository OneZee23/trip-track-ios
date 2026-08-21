import Foundation

/// Where the app decides whether a vehicle's avatar is a drawn sprite or an
/// emoji — and the ONLY place that knows how that is encoded.
///
/// `Vehicle.avatarEmoji` is one string carrying two different kinds of value:
/// an asset name for the pixel-art sprites, and a literal emoji for vehicles
/// created before the sprites existed. Telling them apart used to be five
/// copies of `hasPrefix("pixel_car_")` spread across two build targets — the
/// app, the Live Activity extension, and the social DTOs in between. Every one
/// of those copies falls through to rendering the raw string as text, so the
/// day the naming grows past cars, an un-updated copy prints
/// `pixel_scooter_blue` into somebody's garage instead of drawing anything.
///
/// The prefix is deliberately `pixel_` and not `pixel_car_`: a scooter, a
/// motorcycle and a bicycle are already declared in `VehicleType` and will get
/// sprites of their own. Matching the shorter prefix means a client shipping
/// today still classifies tomorrow's names correctly.
public enum VehicleAvatar {
    /// Marks `avatarEmoji` as an asset name rather than an emoji.
    public static let assetPrefix = "pixel_"

    /// True when the avatar names a drawn sprite in the asset catalog.
    public static func isAsset(_ avatar: String) -> Bool {
        avatar.hasPrefix(assetPrefix)
    }

    /// Stands in wherever a pixel avatar has to be spoken as text — inline
    /// runs, accessibility labels, anywhere an `Image` cannot go.
    public static let textFallback = "🚗"

    // MARK: - The two axes

    /// Two choices, and they travel separately ON PURPOSE.
    ///
    /// `avatarEmoji` carries the COLOUR and never stops being one of the eight
    /// `pixel_car_*` names that every already-installed client can resolve.
    /// The SILHOUETTE rides in its own optional field alongside it.
    ///
    /// The alternative — writing `pixel_scooter_blue` into `avatarEmoji` — is
    /// what makes an old client print `pixel_scooter_blue` into somebody's
    /// garage as literal text, because its check is `hasPrefix("pixel_car_")`
    /// and its fall-through is `Text(avatarEmoji)`. Renaming the prefix does
    /// not help either: the sprite simply is not in that client's bundle and
    /// cannot be put there. Nobody can be forced to update, so the wire value
    /// has to stay drawable by builds that shipped before the scooter existed.
    ///
    /// What an old client sees, therefore, is a car in the right colour —
    /// wrong shape, but a picture, and nothing about the screen looks broken.
    /// Style names must not contain an underscore.

    /// Silhouettes, in picker order. Every entry must have an imageset for
    /// every colour, which `VehicleAvatarCatalogTests` enforces at build time.
    ///
    /// `car` leads and is drawn as a saloon. The id cannot be renamed to
    /// `sedan`: it is baked into the eight `pixel_car_*` names that every
    /// shipped build resolves, and it is what every unknown style falls back
    /// to. A saloon is the most generic car there is, which makes it the right
    /// picture for the value that also means «we do not know».
    ///
    /// Ordered by how many people it fits rather than by size: the ordinary
    /// shapes first, the specific ones after.
    public static let styles: [String] = [
        "car", "hatchback", "crossover", "pickup", "van", "convertible", "sports",
        "motorcycle", "scooter", "bicycle",
    ]

    /// Which silhouettes belong to which behavioural `VehicleType`, keyed by
    /// its raw value because this module cannot see the enum.
    ///
    /// This DOES scope the cosmetic axis by the functional one, which is the
    /// thing Waze is criticised for. The criticism does not apply here: Waze
    /// made people change a type that alters ROUTING in order to get a picture
    /// they liked. Here the type is already a deliberate statement about the
    /// vehicle — it decides whether there is a plate and whether fuel means
    /// anything — and offering a pickup silhouette to somebody who just said
    /// «bicycle» is not freedom, it is a list of wrong answers.
    public static func styles(forType type: String) -> [String] {
        switch type {
        case "moto":    return ["motorcycle"]
        case "moped":   return ["scooter"]
        case "bicycle": return ["bicycle"]
        default:        return ["car", "hatchback", "crossover", "pickup", "van", "convertible", "sports"]
        }
    }

    /// The silhouette a vehicle of this type starts on, and the one it moves to
    /// when the type changes underneath it.
    public static func defaultStyle(forType type: String) -> String {
        styles(forType: type).first ?? defaultStyle
    }

    /// A silhouette that does not belong to the type is not shown and not kept:
    /// leaving a sedan on a vehicle the owner has just called a bicycle is how
    /// the garage ends up drawing cars for motorcycles, which is exactly the
    /// bug this fixes.
    public static func resolveStyle(_ style: String, forType type: String) -> String {
        styles(forType: type).contains(style) ? style : defaultStyle(forType: type)
    }

    /// Colours, ordered by how common they are on real roads rather than by
    /// hue — the first swatch should be the one most people reach for.
    public static let colors: [String] = [
        "white", "black", "silver", "gray", "red", "blue", "orange", "green",
    ]

    public static let defaultStyle = "car"
    public static let defaultColor = "orange"

    public static func compose(style: String, color: String) -> String {
        "\(assetPrefix)\(style)_\(color)"
    }

    /// Nil for emoji avatars and for anything that does not parse — callers
    /// fall back to the default pair rather than guessing.
    public static func decompose(_ avatar: String) -> (style: String, color: String)? {
        guard isAsset(avatar) else { return nil }
        let parts = avatar.dropFirst(assetPrefix.count).split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// The mid-tone of each colour's authored ramp, for the picker swatches.
    /// It is the ramp's BASE rather than its highlight so the swatch reads as
    /// the same paint the sprite is wearing; a highlight-coloured dot makes
    /// every car look a shade darker than the swatch that chose it.
    ///
    /// Kept beside `colors` on purpose — a swatch that has drifted from the
    /// sprite it selects is a bug nobody reports, they just pick another one.
    public static func swatch(_ color: String) -> (r: Double, g: Double, b: Double) {
        switch color {
        case "white":  return (0xEB / 255, 0xED / 255, 0xF2 / 255)
        case "black":  return (0x2A / 255, 0x2C / 255, 0x33 / 255)
        case "silver": return (0xB6 / 255, 0xBA / 255, 0xC2 / 255)
        case "gray":   return (0x70 / 255, 0x75 / 255, 0x80 / 255)
        case "red":    return (0xE0 / 255, 0x3B / 255, 0x2C / 255)
        case "blue":   return (0x3B / 255, 0x7D / 255, 0xD8 / 255)
        case "orange": return (0xF5 / 255, 0x9E / 255, 0x19 / 255)
        case "yellow": return (0xF2 / 255, 0xC4 / 255, 0x1B / 255)
        case "green":  return (0x4C / 255, 0xAF / 255, 0x50 / 255)
        default:       return (0xF5 / 255, 0x9E / 255, 0x19 / 255)
        }
    }

    /// Swatches this pale vanish into a light card without a hairline.
    public static func swatchNeedsBorder(_ color: String) -> Bool {
        let (r, g, b) = swatch(color)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.72
    }

    /// The sprite to draw, from the two fields as they arrive.
    ///
    /// Unknown styles fall back to the car rather than to nothing: a style
    /// added in a later release reaches this client through the feed long
    /// before this client has the sprite for it, and the same reasoning that
    /// protects old builds from new names has to protect this build too.
    ///
    /// Nil only for emoji avatars, which are drawn as text on purpose.
    public static func assetName(style: String?, avatar: String) -> String? {
        guard let (_, color) = decompose(avatar) else { return nil }
        let resolved = style.flatMap { styles.contains($0) ? $0 : nil } ?? defaultStyle
        return compose(style: resolved, color: color)
    }

    /// The colour half of an avatar name, for the picker's swatch selection.
    public static func color(of avatar: String) -> String {
        decompose(avatar)?.color ?? defaultColor
    }

    /// What goes in `avatarEmoji` for a chosen colour — always legacy-safe.
    public static func legacyName(color: String) -> String {
        compose(style: defaultStyle, color: color)
    }

    /// Every offered combination, which is also what the picker draws and what
    /// the catalog test checks. Order is style-major so a colour row keeps its
    /// position as styles are added.
    public static var allAssets: [String] {
        styles.flatMap { style in colors.map { compose(style: style, color: $0) } }
    }
}
