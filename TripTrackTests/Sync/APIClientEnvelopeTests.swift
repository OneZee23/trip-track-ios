import XCTest
@testable import TripTrack

@MainActor
final class APIClientEnvelopeTests: XCTestCase {
    var session: URLSession!
    var client: APIClient!

    override func setUp() async throws {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(session: session, tokenStore: TokenStore.shared)
    }

    struct TestPayload: Codable, Equatable { let value: Int }
    struct TestRequest: Codable { let x: Int }

    func testOkEnvelopeReturnsPayload() async throws {
        MockURLProtocol.requestHandler = { req in
            let body = Data(#"{"status":"ok","payload":{"value":42}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let res: TestPayload = try await client.post("/test", body: TestRequest(x: 1), requiresAuth: false)
        XCTAssertEqual(res, TestPayload(value: 42))
    }

    func testErrorEnvelopeMapsToTypedError() async {
        MockURLProtocol.requestHandler = { req in
            let body = Data(#"{"status":"error","code":"TRIP_NOT_FOUND","message":"not found"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        do {
            let _: TestPayload = try await client.post("/test", body: TestRequest(x: 1), requiresAuth: false)
            XCTFail("expected throw")
        } catch let e as APIError {
            XCTAssertEqual(e, .tripNotFound)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testConflictDetectedError() async {
        MockURLProtocol.requestHandler = { req in
            let body = Data(#"{"status":"error","code":"CONFLICT_DETECTED","message":"conflict","serverVersion":5,"serverLastModifiedAt":"2026-04-19T10:30:45.000Z"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        do {
            let _: TestPayload = try await client.post("/test", body: TestRequest(x: 1), requiresAuth: false)
            XCTFail("expected throw")
        } catch let e as APIError {
            if case .conflictDetected(let version, _) = e {
                XCTAssertEqual(version, 5)
            } else {
                XCTFail("wrong error: \(e)")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
