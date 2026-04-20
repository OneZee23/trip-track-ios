import XCTest
@testable import TripTrack

@MainActor
final class APIClientTokenRefreshTests: XCTestCase {
    var session: URLSession!
    var client: APIClient!

    override func setUp() async throws {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        TokenStore.shared.set(accessToken: "expired", refreshToken: "valid")
        client = APIClient(session: session, tokenStore: TokenStore.shared)
    }

    struct Payload: Codable, Equatable { let v: Int }
    struct Req: Codable { let x: Int }

    func testSingleFlightRefreshOnConcurrent401() async throws {
        let counter = Counter()

        MockURLProtocol.requestHandler = { req in
            let path = req.url!.path
            if path == "/auth/refresh" {
                counter.incrementRefresh()
                let data = Data(#"{"status":"ok","payload":{"accessToken":"new","refreshToken":"newRefresh"}}"#.utf8)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            let tokenHeader = req.value(forHTTPHeaderField: "x-access-token") ?? ""
            if tokenHeader == "expired" {
                counter.incrementLogin()
                let data = Data(#"{"status":"error","code":"USER_NOT_AUTH","message":"expired"}"#.utf8)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            let data = Data(#"{"status":"ok","payload":{"v":1}}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        async let a: Payload = client.post("/foo", body: Req(x: 1), requiresAuth: true)
        async let b: Payload = client.post("/bar", body: Req(x: 2), requiresAuth: true)
        let (pa, pb) = try await (a, b)

        XCTAssertEqual(pa.v, 1)
        XCTAssertEqual(pb.v, 1)
        XCTAssertEqual(counter.refresh, 1, "expected exactly one refresh call")
        XCTAssertGreaterThanOrEqual(counter.login, 2, "both calls should hit 401 first")
    }
}

// Thread-safe counter for test assertions
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _refresh = 0
    private var _login = 0
    var refresh: Int { lock.lock(); defer { lock.unlock() }; return _refresh }
    var login: Int { lock.lock(); defer { lock.unlock() }; return _login }
    func incrementRefresh() { lock.lock(); _refresh += 1; lock.unlock() }
    func incrementLogin() { lock.lock(); _login += 1; lock.unlock() }
}
