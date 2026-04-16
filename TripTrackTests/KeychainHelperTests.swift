// TripTrackTests/KeychainHelperTests.swift
import XCTest
@testable import TripTrack

final class KeychainHelperTests: XCTestCase {

    private let testKey = "com.triptrack.test.keychainHelper"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey)
    }

    func testSaveAndLoadString() throws {
        try KeychainHelper.saveString("hello", for: testKey)
        XCTAssertEqual(KeychainHelper.loadString(key: testKey), "hello")
    }

    func testSaveAndLoadData() throws {
        let data = Data([0x01, 0x02, 0x03])
        try KeychainHelper.save(data, for: testKey)
        XCTAssertEqual(KeychainHelper.load(key: testKey), data)
    }

    func testLoadMissingKeyReturnsNil() {
        XCTAssertNil(KeychainHelper.loadString(key: "com.triptrack.test.nonexistent"))
    }

    func testDelete() throws {
        try KeychainHelper.saveString("delete-me", for: testKey)
        XCTAssertTrue(KeychainHelper.delete(key: testKey))
        XCTAssertNil(KeychainHelper.loadString(key: testKey))
    }

    func testUpsert() throws {
        try KeychainHelper.saveString("v1", for: testKey)
        try KeychainHelper.saveString("v2", for: testKey)
        XCTAssertEqual(KeychainHelper.loadString(key: testKey), "v2")
    }
}
