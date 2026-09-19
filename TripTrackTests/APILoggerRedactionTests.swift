import XCTest
@testable import TripTrack

/// Тело ЗАПРОСА в диагностическом логе обязано маскироваться так же, как
/// тело ответа: `/auth/refresh` шлёт refresh-токен в JSON, `/auth/login` —
/// identity-токен Apple. 17 сен 2026 экспортированный владельцем лог нёс
/// живые refresh-токены открытым текстом — ответы маскировались, запросы нет.
final class APILoggerRedactionTests: XCTestCase {
    func testRefreshTokenInRequestBodyIsMasked() {
        let body = #"{"refreshToken":"eyJhbGciOiJIUzI1NiJ9.payload.sig"}"#
        let out = APILogger.redact(body)
        XCTAssertFalse(out.contains("eyJhbGci"), "refresh-токен уехал в лог: \(out)")
        XCTAssertTrue(out.contains(#""refreshToken":"***""#))
    }

    func testIdentityTokenAndEmailAreMasked() {
        let body = #"{"identityToken":"abc.def.ghi","email":"someone@example.com","fullName":"X"}"#
        let out = APILogger.redact(body)
        XCTAssertFalse(out.contains("abc.def.ghi"))
        XCTAssertFalse(out.contains("someone@example.com"))
    }

    /// `POST /plus/attach` (0.8.0) шлёт подписанный Apple чек телом запроса.
    /// Подпись защищает его от подделки, а не от чтения: это base64-JSON, и
    /// внутри — `originalTransactionId`, `productId`, даты и
    /// `appAccountToken`, равный id аккаунта человека.
    func testSignedTransactionInRequestBodyIsMasked() {
        let body = #"{"signedTransaction":"eyJhbGciOiJFUzI1NiJ9.eyJ0eEQiOjF9.sig"}"#
        let out = APILogger.redact(body)
        XCTAssertFalse(out.contains("eyJhbGci"), "JWS уехал в лог: \(out)")
        XCTAssertTrue(out.contains(#""signedTransaction":"***""#))
    }

    /// Поля, которых в нашем проводе ещё нет, но которые приезжают в ответах
    /// App Store Server API. Список оборонительный нарочно — см.
    /// `PIISensitiveKeys`.
    func testAppleTransactionFieldsAreMasked() {
        for key in ["signedRenewalInfo", "jws", "appAccountToken", "originalTransactionId"] {
            let out = APILogger.redact("{\"\(key)\":\"SECRET-VALUE\"}")
            XCTAssertFalse(out.contains("SECRET-VALUE"), "\(key) не замаскирован: \(out)")
        }
    }

    func testHarmlessBodyStaysReadable() {
        let body = #"{"limit":20,"tripId":"E52CD860"}"#
        XCTAssertEqual(APILogger.redact(body), body)
    }
}
