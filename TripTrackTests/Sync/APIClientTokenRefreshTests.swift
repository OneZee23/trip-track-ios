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

    /// Regression for the 2026-08-23 forced-logout incident: a refresh that
    /// dies on a transient network error (timeout at drive start) must arm a
    /// background recovery retry, NOT wait for the next authed call — during a
    /// recording there IS no next authed call, and the backend's rotation
    /// grace expires unused.
    func testTransientRefreshFailureArmsBackgroundRecovery() async throws {
        let counter = Counter()
        client.refreshRecoveryDelays = [.milliseconds(50), .milliseconds(50)]

        MockURLProtocol.requestHandler = { req in
            let path = req.url!.path
            if path == "/auth/refresh" {
                counter.incrementRefresh()
                if counter.refresh == 1 {
                    throw URLError(.timedOut) // response lost — the incident's failure mode
                }
                let data = Data(#"{"status":"ok","payload":{"accessToken":"recovered","refreshToken":"recoveredRefresh"}}"#.utf8)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            let data = Data(#"{"status":"error","code":"USER_NOT_AUTH","message":"expired"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        // The triggering call fails through to the caller (session kept).
        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("expected the triggering call to fail")
        } catch { /* expected: APIError.network(.timedOut) */ }

        // Recovery should refresh again on its own within the shrunken delays.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(counter.refresh, 2, "background recovery should have re-posted /auth/refresh")
        XCTAssertEqual(TokenStore.shared.accessToken, "recovered", "recovered tokens should be persisted")
    }

    /// A definitive INVALID_REFRESH_TOKEN must go through the injectable
    /// session-death seam (soft expiry preserving local data), never a
    /// destructive sign-out wired directly into the transport layer.
    func testInvalidRefreshTokenFiresSessionDeathHandler() async throws {
        let deathFired = Counter()
        client.sessionDeathHandler = { deathFired.incrementRefresh() }

        MockURLProtocol.requestHandler = { req in
            let path = req.url!.path
            if path == "/auth/refresh" {
                let data = Data(#"{"status":"error","code":"INVALID_REFRESH_TOKEN","message":"Refresh token is invalid or expired"}"#.utf8)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            let data = Data(#"{"status":"error","code":"USER_NOT_AUTH","message":"expired"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("expected the call to fail")
        } catch let e as APIError {
            XCTAssertEqual(e, .invalidRefreshToken)
        }
        XCTAssertEqual(deathFired.refresh, 1, "session death seam should fire exactly once")
    }

    /// A transient refresh failure must NOT fire the session-death seam.
    func testTransientRefreshFailureKeepsSession() async throws {
        let deathFired = Counter()
        client.sessionDeathHandler = { deathFired.incrementRefresh() }
        client.refreshRecoveryDelays = [] // not testing recovery here

        MockURLProtocol.requestHandler = { req in
            if req.url!.path == "/auth/refresh" { throw URLError(.timedOut) }
            let data = Data(#"{"status":"error","code":"USER_NOT_AUTH","message":"expired"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("expected the call to fail")
        } catch { /* expected */ }
        XCTAssertEqual(deathFired.refresh, 0, "transient failure must keep the session")
        XCTAssertNotNil(TokenStore.shared.refreshToken, "refresh token must survive a transient failure")
    }

    /// Review finding: a recovery loop armed for session A must stand down
    /// when the session boundary is crossed (sign-out / sign-in / soft
    /// expiry) — otherwise it refreshes with, or clobbers, the NEXT
    /// session's tokens.
    func testSessionBoundaryCancelsArmedRecovery() async throws {
        let counter = Counter()
        client.refreshRecoveryDelays = [.milliseconds(200)]

        MockURLProtocol.requestHandler = { req in
            if req.url!.path == "/auth/refresh" {
                counter.incrementRefresh()
                throw URLError(.timedOut)
            }
            let data = Data(#"{"status":"error","code":"USER_NOT_AUTH","message":"expired"}"#.utf8)
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        do {
            let _: Payload = try await client.post("/foo", body: Req(x: 1), requiresAuth: true)
            XCTFail("expected the triggering call to fail")
        } catch { /* expected */ }
        XCTAssertEqual(counter.refresh, 1)

        client.sessionBoundaryCrossed() // sign-out / new sign-in happens here

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(counter.refresh, 1, "recovery must not fire across a session boundary")
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
