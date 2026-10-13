import XCTest
@testable import TripTrack

/// APPLE-IOS-8 (Sentry, 77 событий с июля): главный поток висит в
/// `NSRegularExpression` → `replacingOccurrences` внутри `APILogger.redact`.
/// `APIClient` — `@MainActor`, и тело КАЖДОГО запроса целиком шло в журнал
/// через ~25 регулярок. Поездка на 76 000 точек — 6,8 МБ JSON (журнал
/// Sentry 9 окт, 10:49).
final class APILoggerCostTests: XCTestCase {
    private func tripBody(points: Int) -> String {
        let point = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","latitude":52.28123,"longitude":76.95432,"altitude":120.5,"speed":22.25,"course":45,"horizontalAccuracy":4.5,"timestamp":"2026-10-01T08:00:00Z","isInterpolated":false}"#
        return #"{"id":"trip","title":"Павлодар — Омск","trackPoints":["# + Array(repeating: point, count: points).joined(separator: ",") + "]}"
    }

    func testLoggingALargeUploadIsCheap() {
        let body = tripBody(points: 76_000)
        let logger = APILogger()
        var req = URLRequest(url: URL(string: "https://example.invalid/sync/push")!)
        req.httpMethod = "POST"
        let data = Data(body.utf8)
        let t = Date()
        logger.log(request: req, bodyPreview: APILogger.previewText(of: data))
        let ms = Date().timeIntervalSince(t) * 1000
        print("APILoggerCost: \(body.utf8.count / 1_000_000) MB body logged in \(Int(ms)) ms")
        XCTAssertLessThan(ms, 50, "request logging runs on the main actor")
    }

    /// Обрезка не должна открывать секрет, разрезанный посередине: значение
    /// чувствительного поля в начале тела по-прежнему вычищается.
    func testTruncatedPreviewStillRedactsLeadingSecrets() {
        let body = #"{"refreshToken":"secret-value","pad":""# + String(repeating: "x", count: 50_000) + #""}"#
        let preview = APILogger.preview(of: body)
        XCTAssertFalse(preview.contains("secret-value"))
        XCTAssertLessThanOrEqual(preview.count, APILogger.previewLimit + 64)
    }
}
