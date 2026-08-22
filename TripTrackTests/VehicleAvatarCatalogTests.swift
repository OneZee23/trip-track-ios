import XCTest
@testable import TripTrack

/// The Live Activity is a separate build target with its own asset catalog, so
/// every pixel-art vehicle sprite exists twice on disk. That duplication is
/// deliberate — pointing the extension at the app's 432 KB catalog to save the
/// 200 KB of sprites would make the extension bigger, not smaller — but it is
/// maintained by hand, and a hand-maintained copy is a copy somebody forgets.
///
/// Forgetting is silent: the lock-screen avatar falls back to nothing while the
/// in-app one looks fine, so it survives every check that does not lock the
/// phone. These tests make it loud at build time instead.
final class VehicleAvatarCatalogTests: XCTestCase {

    private static let repoRoot: URL = {
        // .../TripTrackTests/VehicleAvatarCatalogTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private func imagesetNames(at path: String) throws -> Set<String> {
        let dir = Self.repoRoot.appendingPathComponent(path)
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return Set(
            entries
                .filter { $0.hasSuffix(".imageset") }
                .map { String($0.dropLast(".imageset".count)) }
                .filter { VehicleAvatar.isAsset($0) }
        )
    }

    func testBothTargetsShipTheSameVehicleSprites() throws {
        let app = try imagesetNames(at: "TripTrack/Resources/Assets.xcassets")
        let liveActivity = try imagesetNames(at: "TripTrackLiveActivity/Assets.xcassets")

        XCTAssertFalse(app.isEmpty, "found no pixel_ sprites in the app catalog — check the path")

        let missingFromLiveActivity = app.subtracting(liveActivity)
        XCTAssertTrue(
            missingFromLiveActivity.isEmpty,
            "these sprites exist in the app but not in the Live Activity catalog, "
            + "so the lock screen will render them blank: "
            + missingFromLiveActivity.sorted().joined(separator: ", ")
        )

        let orphaned = liveActivity.subtracting(app)
        XCTAssertTrue(
            orphaned.isEmpty,
            "these sprites exist only in the Live Activity catalog and are dead weight: "
            + orphaned.sorted().joined(separator: ", ")
        )
    }

    /// `Vehicle.pixelCarAssets` is what the picker offers. An entry with no
    /// imageset behind it is an empty tile the user can select.
    func testEveryOfferedAvatarHasAnImageset() throws {
        let app = try imagesetNames(at: "TripTrack/Resources/Assets.xcassets")
        let missing = Vehicle.pixelCarAssets.filter { !app.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            "offered in the picker but absent from the asset catalog: "
            + missing.sorted().joined(separator: ", ")
        )
    }

    /// The prefix is the contract between the two targets. If an avatar name
    /// stops matching it, `VehicleAvatar.isAsset` sends it down the emoji path
    /// and the raw string gets printed as text.
    func testOfferedAvatarsAllMatchTheAssetPrefix() {
        for name in Vehicle.pixelCarAssets {
            XCTAssertTrue(
                VehicleAvatar.isAsset(name),
                "\(name) does not match VehicleAvatar.assetPrefix and would render as literal text"
            )
        }
    }
}

/// The rule that keeps already-installed builds from printing raw strings into
/// somebody's garage: whatever goes into `avatarEmoji` must stay a name that a
/// client shipped before this style existed can still resolve.
final class VehicleAvatarWireCompatibilityTests: XCTestCase {

    /// What every build up to 0.6.1 does, reproduced verbatim. If this stops
    /// matching, those builds fall through to `Text(avatarEmoji)`.
    private func legacyClientCanRender(_ avatar: String) -> Bool {
        avatar.hasPrefix("pixel_car_")
            && ["orange", "red", "blue", "green", "gray", "black", "white", "silver"]
                .contains(String(avatar.dropFirst("pixel_car_".count)))
    }

    func testEveryColourProducesALegacyDrawableName() {
        for color in VehicleAvatar.colors {
            let wire = VehicleAvatar.legacyName(color: color)
            XCTAssertTrue(
                legacyClientCanRender(wire),
                "\(wire) is not one of the eight names a 0.6.1 client has in its bundle — "
                + "that client would draw the string as text"
            )
        }
    }

    /// A silhouette this build has never heard of must land on the car, not on
    /// a missing image. The same courtesy old builds get from us.
    func testUnknownStyleFallsBackToTheCar() {
        let wire = VehicleAvatar.legacyName(color: "red")
        XCTAssertEqual(VehicleAvatar.assetName(style: "hovercraft", avatar: wire), "pixel_car_red")
        XCTAssertEqual(VehicleAvatar.assetName(style: nil, avatar: wire), "pixel_car_red")
    }

    /// An emoji avatar has no sprite and must say so rather than compose one.
    func testEmojiAvatarHasNoAsset() {
        XCTAssertNil(VehicleAvatar.assetName(style: "car", avatar: "🏎️"))
    }

    func testColourSurvivesARoundTrip() {
        for color in VehicleAvatar.colors {
            let wire = VehicleAvatar.legacyName(color: color)
            XCTAssertEqual(VehicleAvatar.color(of: wire), color)
        }
    }

    /// The vehicle a fresh install starts with must itself be legacy-drawable.
    func testDefaultVehicleIsWireSafe() {
        let v = Vehicle(avatarEmoji: VehicleAvatar.legacyName(color: VehicleAvatar.defaultColor))
        XCTAssertTrue(legacyClientCanRender(v.avatarEmoji))
        XCTAssertEqual(v.avatarStyle, VehicleAvatar.defaultStyle)
    }
}

/// The silhouette must belong to the type it is drawn on. A saloon on a
/// bicycle is the bug the first build shipped with, and it is reachable from
/// three directions: an old payload, a type changed on another device, and a
/// style list that grows.
final class VehicleAvatarTypeScopingTests: XCTestCase {

    func testEveryTypeOffersAtLeastOneSilhouette() {
        for type in VehicleType.allCases {
            XCTAssertFalse(
                VehicleAvatar.styles(forType: type.rawValue).isEmpty,
                "\(type.rawValue) has no silhouette — the picker would show an empty row"
            )
        }
    }

    func testEveryScopedSilhouetteIsADeclaredStyle() {
        for type in VehicleType.allCases {
            for style in VehicleAvatar.styles(forType: type.rawValue) {
                XCTAssertTrue(
                    VehicleAvatar.styles.contains(style),
                    "\(style) is offered for \(type.rawValue) but is not in the master list, "
                    + "so no test checks it has sprites"
                )
            }
        }
    }

    /// No silhouette may sit under two types — otherwise changing the type
    /// keeps a shape that now means something else.
    func testScopesDoNotOverlap() {
        var seen: [String: String] = [:]
        for type in VehicleType.allCases {
            for style in VehicleAvatar.styles(forType: type.rawValue) {
                if let other = seen[style] {
                    XCTFail("\(style) belongs to both \(other) and \(type.rawValue)")
                }
                seen[style] = type.rawValue
            }
        }
    }

    func testAMismatchedPairResolvesToTheTypesOwnSilhouette() {
        XCTAssertEqual(VehicleAvatar.resolveStyle("pickup", forType: "bicycle"), "bicycle")
        XCTAssertEqual(VehicleAvatar.resolveStyle("car", forType: "moto"), "motorcycle")
        XCTAssertEqual(VehicleAvatar.resolveStyle("sports", forType: "car"), "sports")
        // Unknown type falls to the car scope, matching `VehicleType.init(storage:)`.
        XCTAssertEqual(VehicleAvatar.resolveStyle("van", forType: "hovercraft"), "van")
    }

    /// The whole point, stated as the user would: a vehicle called a
    /// motorcycle draws a motorcycle, no matter what the stored style says.
    func testAMotorcycleNeverDrawsACar() {
        let v = Vehicle(
            avatarEmoji: VehicleAvatar.legacyName(color: "red"),
            avatarStyle: "car",
            type: .moto
        )
        XCTAssertEqual(v.avatarImageName, "pixel_motorcycle_red")
    }

    func testEveryScopedSilhouetteHasSpritesInEveryColour() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Resources/Assets.xcassets")
        let present = Set(
            (try FileManager.default.contentsOfDirectory(atPath: dir.path))
                .filter { $0.hasSuffix(".imageset") }
                .map { String($0.dropLast(".imageset".count)) }
        )
        for type in VehicleType.allCases {
            for style in VehicleAvatar.styles(forType: type.rawValue) {
                for color in VehicleAvatar.colors {
                    let name = VehicleAvatar.compose(style: style, color: color)
                    XCTAssertTrue(present.contains(name), "missing sprite \(name)")
                }
            }
        }
    }
}

/// Illustrations referenced by name are the one asset kind the compiler cannot
/// check: `Image("empty_roads")` with a typo builds clean and renders nothing,
/// and it renders nothing on a screen nobody visits until something has gone
/// wrong — which is exactly when a blank hero is worst.
final class BrandAssetReferenceTests: XCTestCase {

    private static let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TripTrack/Resources/Assets.xcassets")

    private func imagesets() throws -> Set<String> {
        Set(
            (try FileManager.default.contentsOfDirectory(atPath: Self.catalog.path))
                .filter { $0.hasSuffix(".imageset") }
                .map { String($0.dropLast(".imageset".count)) }
        )
    }

    /// Every name passed to `EmptyStateIllustration` anywhere in the app.
    /// Scraped rather than listed by hand — a list would drift the first time
    /// somebody added a screen.
    private func referencedNames() throws -> Set<String> {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TripTrack/Views")
        var found = Set<String>()
        let pattern = try NSRegularExpression(
            pattern: #"EmptyStateIllustration\(name:\s*"([A-Za-z0-9_]+)""#
        )
        guard let walker = FileManager.default.enumerator(atPath: views.path) else { return found }
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: views.appendingPathComponent(rel), encoding: .utf8)
            let ns = text as NSString
            for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                found.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        return found
    }

    func testEveryIllustrationNameResolvesToAnImageset() throws {
        let refs = try referencedNames()
        XCTAssertFalse(refs.isEmpty, "found no EmptyStateIllustration call sites — has it been renamed?")
        let present = try imagesets()
        let missing = refs.subtracting(present)
        XCTAssertTrue(
            missing.isEmpty,
            "referenced but absent from the asset catalog: " + missing.sorted().joined(separator: ", ")
        )
    }

    /// Every club in the seeded catalogue draws a mark. A club whose artwork is
    /// missing silently falls back to its emoji, which is the state this whole
    /// pass exists to remove.
    func testEveryClubHasItsMark() throws {
        let present = try imagesets()
        for club in Club.all {
            guard let asset = club.asset else { continue }
            XCTAssertTrue(present.contains(asset), "club \(club.id) has no \(asset) imageset")
        }
    }
}

/// The sprite metrics are generated from the installed art, and layout depends
/// on them being true. A stale table is a silent layout bug: the car simply
/// sits wrong on its plate, which is what «huge empty space above the car»
/// looked like before the table existed.
final class VehicleSpriteMetricsTests: XCTestCase {

    func testEveryStyleHasRealMetrics() {
        for style in VehicleAvatar.styles {
            let b = VehicleSpriteMetrics.inkBounds(style: style)
            XCTAssertTrue(
                b.top >= 0 && b.bottom <= 1 && b.bottom > b.top,
                "\(style) has nonsense bounds \(b) — is the table generated?"
            )
            XCTAssertNotEqual(
                b.top, 0.0, accuracy: 0.0001,
                "\(style) fell through to the default branch, so it is missing from the table"
            )
        }
    }

    /// The set shares a ground line, so every silhouette must end at the same
    /// place. If one drifts, the vehicles stop standing on the same floor.
    func testEverySilhouetteSharesTheGroundLine() {
        let bottoms = VehicleAvatar.styles.map { VehicleSpriteMetrics.inkBounds(style: $0).bottom }
        let lo = bottoms.min() ?? 0
        let hi = bottoms.max() ?? 0
        XCTAssertLessThan(
            hi - lo, 0.02,
            "silhouettes end at different heights (\(lo)…\(hi)) — the set is no longer normalised"
        )
    }

    /// Taller vehicles must still measure taller, or the crop has flattened the
    /// proportions that tell the silhouettes apart.
    func testAVanIsTallerThanAHatchback() {
        XCTAssertGreaterThan(
            VehicleSpriteMetrics.inkHeight(style: "van"),
            VehicleSpriteMetrics.inkHeight(style: "hatchback")
        )
        XCTAssertGreaterThan(
            VehicleSpriteMetrics.inkHeight(style: "crossover"),
            VehicleSpriteMetrics.inkHeight(style: "car")
        )
    }

    /// An unknown style must land on a neutral full-frame reading rather than
    /// on some other silhouette's offsets.
    func testUnknownStyleGetsTheIdentityBounds() {
        let b = VehicleSpriteMetrics.inkBounds(style: "hovercraft")
        XCTAssertEqual(b.top, 0.0, accuracy: 0.0001)
        XCTAssertEqual(b.bottom, 1.0, accuracy: 0.0001)
        XCTAssertEqual(VehicleSpriteMetrics.centeringOffset(style: "hovercraft"), 0.0, accuracy: 0.0001)
    }
}
