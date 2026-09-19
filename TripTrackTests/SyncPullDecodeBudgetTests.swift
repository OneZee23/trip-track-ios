import XCTest
@testable import TripTrack

/// Budget for `APIClient.decodeEnvelope` — the nonisolated decode step that
/// used to run `decoder.decode(...)` synchronously on `@MainActor`
/// `APIClient`. On a `/sync/pull` response carrying hundreds of trips that
/// decode runs the custom ISO8601 date strategy through a `DateFormatter`
/// call per timestamp field, real CPU work that competed with the main
/// thread. `decodeEnvelope` itself is `private`, so this measures the SAME
/// decode shape it uses (fresh `JSONDecoder`, identical date strategy)
/// against a realistic 500-trip fixture — same measurement pattern as
/// `MapRenderCostTests` (warm up once, then time repeated rounds).
final class SyncPullDecodeBudgetTests: XCTestCase {
    /// Mirrors `APIEnvelope<T>`'s wire shape for ENCODING the fixture —
    /// `APIEnvelope` itself is `Decodable`-only (it never needs to be sent),
    /// so building the JSON bytes needs a local Encodable twin with the same
    /// field names.
    private struct WireEnvelope<T: Encodable>: Encodable {
        let status: String
        let payload: T?
        let code: String?
        let message: String?
        let serverVersion: Int?
        let serverLastModifiedAt: String?
    }

    /// Metadata-only trip, matching what `/sync/pull` actually sends
    /// (`TripSyncPayload.trackPoints`'s doc comment: delta sync omits
    /// track points). `isTransfer`/`checkpoints`/`segments`/`source` are all
    /// `var` Optionals — the memberwise init defaults them to `nil`, same as
    /// `SyncChunkBudgetTests.payload(points:)` relies on.
    private func trip(_ i: Int) -> TripSyncPayload {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 3_600)
        return TripSyncPayload(
            id: UUID(), title: "Краснодар → Джубга #\(i)",
            description: i % 4 == 0 ? "заметка о поездке номер \(i)" : nil,
            startDate: start, endDate: start.addingTimeInterval(5_400),
            distance: 120_450 + Double(i % 500) * 37, maxSpeed: 31.4, averageSpeed: 16.7,
            fuelUsed: 8.9, elevation: 610, maxAltitude: 740, drivingTime: 5_100, stoppedTime: 300,
            region: i % 2 == 0 ? "Краснодарский край" : "Ростовская область",
            isPrivate: i % 3 == 0, vehicleId: UUID(), fuelCurrency: "RUB",
            previewPolyline: Data(repeating: UInt8(i % 255), count: 220).base64EncodedString(),
            badgesJson: nil, xpEarned: 40 + i % 60,
            conflictVersion: 1, lastModifiedAt: start.addingTimeInterval(5_400),
            serverCreatedAt: start, trackPoints: nil, photos: nil)
    }

    private func fixtureData(tripCount: Int) throws -> Data {
        let response = SyncPullResponse(
            trips: .init(upserted: (0..<tripCount).map(trip), deleted: []),
            vehicles: .init(upserted: [], deleted: []),
            photos: .init(upserted: [], deleted: []),
            settings: nil,
            serverTime: ISODate.format(Date(timeIntervalSince1970: 1_700_500_000)),
            ownedCounts: nil, journeys: nil, discoveries: nil)
        let envelope = WireEnvelope(
            status: "ok", payload: response, code: nil, message: nil,
            serverVersion: nil, serverLastModifiedAt: nil)
        // Same date-encoding strategy as `APIClient.serializeBody`.
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(ISODate.format(date))
        }
        return try enc.encode(envelope)
    }

    /// Exact shape of `APIClient.decodeEnvelope` — a fresh `JSONDecoder` per
    /// call (neither type is `Sendable`), same custom ISO8601 strategy.
    private func decodeOnce(_ data: Data) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = ISODate.parse(s) { return date }
            throw APIError.decoding("invalid ISO8601: \(s)")
        }
        _ = try dec.decode(APIEnvelope<SyncPullResponse>.self, from: data)
    }

    /// Not a target, a budget: this is CPU work that (since this task) runs
    /// off `@MainActor` — but it still has to be cheap enough that a
    /// background-pool hop doesn't itself become the next "~200ms freeze"
    /// class of bug (see `FeedViewModel.loadTripsAsync`'s docstring for that
    /// exact symptom on the load side).
    func testDecode500TripsFitsBudget() throws {
        let data = try fixtureData(tripCount: 500)
        try decodeOnce(data) // warm up: formatter/allocator caches
        let rounds = 10
        let start = Date()
        for _ in 0..<rounds { try decodeOnce(data) }
        let perCall = Date().timeIntervalSince(start) / Double(rounds)
        XCTAssertLessThan(
            perCall, 0.5,
            "decoding 500 trips took \(perCall)s/call — over budget")
    }
}
