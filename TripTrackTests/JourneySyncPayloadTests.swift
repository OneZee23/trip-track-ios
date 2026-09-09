import XCTest
@testable import TripTrack

final class JourneySyncPayloadTests: XCTestCase {
    /// `APIClient` has no shared `JSONEncoder`/`JSONDecoder` static — its coders
    /// are built inline (`init` / `serializeBody`) around the custom
    /// `ISODate`-based strategy. Mirrored here so this test exercises the same
    /// wire format the real transport uses, not `Foundation`'s `.iso8601`.
    private static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISODate.format(date))
        }
        return enc
    }

    private static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = ISODate.parse(s) { return date }
            throw APIError.decoding("invalid ISO8601: \(s)")
        }
        return dec
    }

    /// Старый сервер секции `journeys` не отдаёт — pull обязан декодироваться.
    func testPullWithoutJourneysSectionDecodes() throws {
        let json = """
        {"trips":{"upserted":[],"deleted":[]},"vehicles":{"upserted":[],"deleted":[]},
         "photos":{"upserted":[],"deleted":[]},"settings":null,"serverTime":"2026-09-09T10:00:00.000Z"}
        """.data(using: .utf8)!
        let r = try Self.makeDecoder().decode(SyncPullResponse.self, from: json)
        XCTAssertNil(r.journeys)
    }

    func testPayloadRoundTripsExcludedIdsAndOpenEnd() throws {
        let j = Journey(startDate: Date(timeIntervalSince1970: 1_760_000_000), endDate: nil, excludedTripIds: [UUID()])
        let data = try Self.makeEncoder().encode(JourneySyncPayload(journey: j))
        let back = try Self.makeDecoder().decode(JourneySyncPayload.self, from: data)
        XCTAssertEqual(back.id, j.id)
        XCTAssertNil(back.endDate)
        XCTAssertEqual(back.excludedTripIds, j.excludedTripIds)
    }
}
