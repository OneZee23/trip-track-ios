import XCTest
@testable import TripTrack

/// «Стереть мои данные с сервера» обязано забирать и заявки о находках.
///
/// История у кнопки ровно такая: до 0.6.4 она удаляла только поездки, и у
/// человека, который ею воспользовался, на сервере оставался публичный гараж.
/// Находки — тот же случай: `secret_find` знает, где человек был и когда, и
/// уйти он обязан вместе с остальным.
///
/// Проверяется шаг, а не весь `wipeServerData`: тот ходит по базе и зовёт
/// `APIClient.shared`, подменить который нечем, — поэтому шаг вынесен в
/// `forgetServerDiscoveries(client:)` и зовётся из вайпа одной строкой.
@MainActor
final class DiscoveryForgetAllTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    /// Сессия гасится руками: незакрытая `URLSession` держит и очередь, и
    /// `MockURLProtocol` до конца прогона — и роняет ЧУЖОЙ класс.
    override func tearDown() {
        MockURLProtocol.reset()
        session?.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    private func serve(status: Int) {
        MockURLProtocol.requestHandler = { req in
            let response = HTTPURLResponse(
                url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"ok","payload":{}}"#.utf8))
        }
    }

    func testWipeAsksTheServerToForgetEveryFind() async {
        serve(status: 200)
        let client = APIClient(session: session, tokenStore: .shared)

        await AuthService.shared.forgetServerDiscoveries(client: client)

        let sent = MockURLProtocol.recordedRequests.map { ($0.url?.path ?? "", $0.httpMethod ?? "") }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.0, "/secrets/forget-all")
        XCTAssertEqual(sent.first?.1, "POST")
    }

    /// Упавший запрос не роняет вайп: остальные сущности удаляются так же, по
    /// одной и независимо друг от друга.
    func testFailureDoesNotThrow() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let client = APIClient(session: session, tokenStore: .shared)

        await AuthService.shared.forgetServerDiscoveries(client: client)

        XCTAssertFalse(MockURLProtocol.recordedRequests.isEmpty)
    }
}
