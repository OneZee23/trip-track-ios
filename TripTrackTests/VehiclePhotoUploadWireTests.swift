import XCTest
@testable import TripTrack

/// Фото машины: идентификаторы в multipart-форме уезжают СТРОЧНЫМИ.
///
/// Postgres хранит `uuid` каноническим строчным hex, `UUID.uuidString` печатает
/// заглавные; сервер до хотфикса `100d8b7` сравнивал их как строки, и первое
/// фото каждой машины падало в `photoNotFound` уже после загрузки байтов —
/// так у людей на 0.6.4–0.7.0 ни одно фото машины не синхронизировалось.
/// Сервер починен, но прод обновляется отдельно от приложения: клиент обязан
/// работать и против ещё не выкаченного сервера.
@MainActor
final class VehiclePhotoUploadWireTests: XCTestCase {
    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session?.invalidateAndCancel()
        session = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testVehiclePhotoFormCarriesLowercaseIdentifiers() async throws {
        MockURLProtocol.requestHandler = { req in
            let body = #"{"status":"ok","payload":{"photoId":"x","thumbnailUrl":"t","remoteUrl":"r"}}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        let storage = R2PhotoStorage(client: APIClient(session: session, tokenStore: TokenStore.shared))
        let vehicleId = UUID(uuidString: "FB701CDD-1111-4222-8333-444455556666")!
        let photoId = UUID(uuidString: "ABCDEF01-2345-4678-9ABC-DEF012345678")!

        _ = try? await storage.uploadVehiclePhotoPart(
            vehicleId: vehicleId, photoId: photoId, type: .thumbnail,
            data: Data(repeating: 0xFF, count: 16), isMain: true, takenAt: Date(),
            metadataAlreadyClean: true)

        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        let body = Self.bodyString(of: req)
        XCTAssertTrue(body.contains("fb701cdd-1111-4222-8333-444455556666"), "vehicleId обязан быть строчным")
        XCTAssertTrue(body.contains("abcdef01-2345-4678-9abc-def012345678"), "photoId обязан быть строчным")
        XCTAssertFalse(body.contains("FB701CDD"), "заглавный UUID ломает сервер до хотфикса")
    }

    private static func bodyString(of req: URLRequest) -> String {
        if let data = req.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = req.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
