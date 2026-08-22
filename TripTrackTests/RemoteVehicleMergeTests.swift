import XCTest
import CoreData
@testable import TripTrack

/// The silhouette is the one thing in 0.6.2 that the backend does not know
/// about yet, which makes `applyRemoteVehicle` the place where the release can
/// quietly undo itself.
///
/// `avatarStyle` shipped as an unconditional assignment with a `?? "car"`
/// default, while the five optional fields beside it all kept the local value
/// when the server said nothing. That difference is the whole bug: a server
/// without the column omits the field, absence read as «car», and the pull
/// that follows an upload — the one the upload itself provokes — turned the
/// scooter the person had just picked back into a saloon. Not a corner case:
/// no backend has the column, so it was every pull for every signed-in user.
///
/// These tests pin the distinction between «the server says car» and «the
/// server has no opinion», in both directions, so the field cannot drift back
/// to matching its own default.
final class RemoteVehicleMergeTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    override func tearDown() {
        repo = nil
        pc = nil
        super.tearDown()
    }

    @discardableResult
    private func makeLocal(id: UUID, style: String, type: String = "moped") -> VehicleEntity {
        let e = VehicleEntity(context: pc.container.viewContext)
        e.id = id
        e.name = "Vespa"
        e.avatarEmoji = VehicleAvatar.legacyName(color: "blue")
        e.avatarStyle = style
        e.vehicleType = type
        e.odometerKm = 120
        e.vehicleLevel = 2
        e.lastModifiedAt = Date()
        return e
    }

    private func payload(id: UUID, avatarStyle: String?) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: id,
            name: "Vespa",
            avatarEmoji: VehicleAvatar.legacyName(color: "blue"),
            odometerKm: 120,
            level: 2,
            stickersJson: nil,
            cityConsumption: 0,
            highwayConsumption: 0,
            fuelPrice: 0,
            conflictVersion: 1,
            lastModifiedAt: Date(),
            avatarStyle: avatarStyle
        )
    }

    private func fetch(_ id: UUID) -> VehicleEntity? {
        let req: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? pc.container.viewContext.fetch(req).first
    }

    /// The incident itself: a backend with no column omits the field, and the
    /// phone must keep what its owner chose.
    func testSilentServerDoesNotResetSilhouette() {
        let id = UUID()
        makeLocal(id: id, style: "scooter")

        repo.applyRemoteVehicle(payload(id: id, avatarStyle: nil))

        XCTAssertEqual(
            fetch(id)?.avatarStyle, "scooter",
            "a server that never shipped the column must not be read as saying «car» — "
            + "that turns every sync into an undo of the pick the user just made"
        )
    }

    /// The other direction, so the fix is not «ignore the server». Once the
    /// column exists, a real value still wins: that is how a change made on the
    /// iPad reaches the iPhone.
    func testServerValueOverwritesLocalSilhouette() {
        let id = UUID()
        makeLocal(id: id, style: "scooter")

        repo.applyRemoteVehicle(payload(id: id, avatarStyle: "motorcycle"))

        XCTAssertEqual(fetch(id)?.avatarStyle, "motorcycle")
    }

    /// «car» sent deliberately is a value like any other. Distinguishing it
    /// from silence is the entire point — a server that has the column and
    /// holds a saloon must be able to say so.
    func testServerCanDeliberatelySayCar() {
        let id = UUID()
        makeLocal(id: id, style: "scooter")

        repo.applyRemoteVehicle(payload(id: id, avatarStyle: VehicleAvatar.defaultStyle))

        XCTAssertEqual(fetch(id)?.avatarStyle, VehicleAvatar.defaultStyle)
    }

    /// A vehicle arriving for the first time from a silent server has no local
    /// value to keep. It must still end up drawable rather than nil, because
    /// `Vehicle.avatarImageName` composes the asset name from this field.
    func testNewVehicleFromSilentServerIsStillDrawable() {
        let id = UUID()

        repo.applyRemoteVehicle(payload(id: id, avatarStyle: nil))

        let stored = fetch(id)
        XCTAssertNotNil(stored)
        let style = stored?.avatarStyle ?? VehicleAvatar.defaultStyle
        XCTAssertNotNil(
            VehicleAvatar.assetName(style: style, avatar: stored?.avatarEmoji ?? ""),
            "a vehicle pulled from a column-less server must still resolve to a sprite"
        )
    }

    /// The five neighbours this field should have matched from the start. If
    /// any of them ever regresses to an unconditional assignment, the same
    /// incident happens to plates and privacy instead.
    func testSilentServerLeavesOtherOptionalFieldsAlone() {
        let id = UUID()
        let local = makeLocal(id: id, style: "scooter")
        local.plate = "A123AA777"
        local.plateVisible = true
        local.visibleToOthers = false

        repo.applyRemoteVehicle(payload(id: id, avatarStyle: nil))

        let stored = fetch(id)
        XCTAssertEqual(stored?.vehicleType, "moped")
        XCTAssertEqual(stored?.plate, "A123AA777")
        XCTAssertEqual(stored?.plateVisible, true)
        XCTAssertEqual(stored?.visibleToOthers, false)
    }
}
