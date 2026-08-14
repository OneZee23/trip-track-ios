import XCTest
@testable import TripTrack

/// Coverage for what a vehicle shows to someone who is not its owner.
///
/// A registration plate is PII: in Russia it is enough to look up the
/// registered owner's name and address. So the default is hidden and every
/// route to showing it has to be a deliberate act. These tests exist to fail
/// loudly if that default ever inverts.
final class VehiclePrivacyTests: XCTestCase {

    private func car(
        plate: String = "А 123 БВ 77",
        plateVisible: Bool = false,
        visibleToOthers: Bool = true,
        type: VehicleType = .car
    ) -> Vehicle {
        Vehicle(name: "Honda Civic", type: type, plate: plate,
                plateVisible: plateVisible, visibleToOthers: visibleToOthers)
    }

    // MARK: - The default

    /// A vehicle created without saying anything about its plate hides it.
    func testPlateIsHiddenByDefault() {
        XCTAssertFalse(Vehicle(name: "X").plateVisible)
        XCTAssertNil(car().publicPlate)
    }

    /// The owner still sees their own plate — hiding is about other people.
    func testOwnerAlwaysHasThePlate() {
        let v = car()
        XCTAssertTrue(v.hasPlate)
        XCTAssertEqual(v.plate, "А 123 БВ 77")
    }

    // MARK: - Opting in

    func testOptingInRevealsThePlate() {
        XCTAssertEqual(car(plateVisible: true).publicPlate, "А 123 БВ 77")
    }

    /// Hiding the whole vehicle hides the plate with it, even if the plate
    /// toggle was left on. The two switches are independent, but the outer one
    /// wins — otherwise «Показывать транспорт: выкл» would still leak a plate.
    func testHiddenVehicleLeaksNothing() {
        XCTAssertNil(car(plateVisible: true, visibleToOthers: false).publicPlate)
    }

    // MARK: - Types that carry no plate

    /// A bicycle has no plate to show, however the flags are set.
    func testTypeWithoutPlatesNeverShowsOne() {
        let bike = car(plate: "SOMETHING", plateVisible: true, type: .bicycle)
        XCTAssertFalse(bike.hasPlate)
        XCTAssertNil(bike.publicPlate)
    }

    func testEmptyPlateIsNotAPlate() {
        XCTAssertFalse(car(plate: "").hasPlate)
        XCTAssertNil(car(plate: "", plateVisible: true).publicPlate)
    }

    // MARK: - Type capabilities

    /// The form hides sections by these flags, so they are load-bearing.
    func testTypeCapabilities() {
        XCTAssertTrue(VehicleType.car.hasPlate)
        XCTAssertTrue(VehicleType.moto.hasPlate)
        XCTAssertFalse(VehicleType.moped.hasPlate)
        XCTAssertFalse(VehicleType.bicycle.hasPlate)

        XCTAssertTrue(VehicleType.moped.burnsFuel)
        XCTAssertFalse(VehicleType.bicycle.burnsFuel)

        XCTAssertTrue(VehicleType.car.supportsAutoRecord)
        XCTAssertTrue(VehicleType.moto.supportsAutoRecord)
        XCTAssertFalse(VehicleType.moped.supportsAutoRecord)
        XCTAssertFalse(VehicleType.bicycle.supportsAutoRecord)
    }

    /// Vehicles written before the type column existed decode as plated cars,
    /// which is what every one of them was.
    func testUnknownStoredTypeFallsBackToCar() {
        XCTAssertEqual(VehicleType(storage: nil), .car)
        XCTAssertEqual(VehicleType(storage: ""), .car)
        XCTAssertEqual(VehicleType(storage: "spaceship"), .car)
        XCTAssertEqual(VehicleType(storage: "bicycle"), .bicycle)
    }

    // MARK: - Decoding old payloads

    /// A server that has not shipped the new columns sends none of them; the
    /// vehicle must still decode, as a visible car with no plate.
    func testDecodesPayloadWithoutTheNewFields() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","avatarEmoji":"🚗","odometerKm":120,
         "level":2,"createdAt":0,"cityConsumption":10,"highwayConsumption":6,"fuelPrice":56}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let v = try decoder.decode(Vehicle.self, from: Data(json.utf8))
        XCTAssertEqual(v.type, .car)
        XCTAssertEqual(v.plate, "")
        XCTAssertFalse(v.plateVisible)
        XCTAssertTrue(v.visibleToOthers)
    }
}
