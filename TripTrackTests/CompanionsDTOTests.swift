import XCTest
@testable import TripTrack

/// Decoding coverage for the `/companions/*` DTOs
/// (`TripTrack/Models/Social/CompanionsDTOs.swift`). Every fixture below is
/// either a verbatim JSON body recorded against a live server in
/// `trip-track-backend/.superpowers/sdd/2026-08-11-companions-backend/task-10-report.md`
/// (accounts: Driver A = a1db2427-2a15-4496-9dd5-efc29edea5f8, Companion B =
/// 1efcd7ab-cd57-414e-a3ae-d5ed996991f3, trip = 9c29078a-3b90-4a48-8469-206f4d641912),
/// or — where noted per-test — a schema-faithful reconstruction using real
/// values from that report because the exact case wasn't literally captured
/// in a live response (e.g. a pending row through `/companions/list`
/// specifically). Assertions check actual field VALUES, not just that
/// decoding succeeded.
final class CompanionsDTOTests: XCTestCase {

    /// Mirrors `APIClient`'s private decoder: the server sends dates as
    /// ISO-8601 strings, so a plain `JSONDecoder` (which expects a Double
    /// under `.deferredToDate`) can't read them. `CompanionInvitePreview`
    /// and `SocialFeedTrip` both have `Date` fields, so tests decoding
    /// those need this same strategy.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = ISODate.parse(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid ISO8601: \(s)")
            }
            return date
        }
        return d
    }()

    private let companionB = UUID(uuidString: "1efcd7ab-cd57-414e-a3ae-d5ed996991f3")!
    private let driverA = UUID(uuidString: "a1db2427-2a15-4496-9dd5-efc29edea5f8")!
    private let tripId = UUID(uuidString: "9c29078a-3b90-4a48-8469-206f4d641912")!

    // MARK: - /companions/list

    /// Real recorded shape (task-10 step 9, B's own view after accepting):
    /// `{"items":[{"accountId":"1efcd7ab-...","displayName":"Companion B","avatarEmoji":"🚗","status":1}],"isOwnerView":false}`
    func testListItemStatusAccepted() throws {
        let json = Data(#"""
        {"items":[{"accountId":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","displayName":"Companion B","avatarEmoji":"🚗","status":1}],"isOwnerView":false}
        """#.utf8)
        let res = try decoder.decode(CompanionsListResponse.self, from: json)
        XCTAssertEqual(res.items.count, 1)
        XCTAssertEqual(res.items[0].accountId, companionB)
        XCTAssertEqual(res.items[0].displayName, "Companion B")
        XCTAssertEqual(res.items[0].avatarEmoji, "🚗")
        XCTAssertEqual(res.items[0].status, .accepted)
        XCTAssertFalse(res.isOwnerView)
    }

    /// The live scenario never captured a `list` response with a PENDING
    /// row through this exact endpoint (the only status:0 response on record
    /// is `/companions/invite`'s differently-shaped `{companion:{...}}` —
    /// covered separately below). This fixture reconstructs the `list` shape
    /// (same field names/real ids as the accepted-row fixture above) with
    /// `status: 0`, which is `CompanionStatus.Pending` per
    /// `trip-companion.entity.ts`, and `isOwnerView: true` — pending rows are
    /// only ever shown to the owner (`CompanionsService.list`'s filter).
    func testListItemStatusPending() throws {
        let json = Data(#"""
        {"items":[{"accountId":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","displayName":"Companion B","avatarEmoji":"🚗","status":0}],"isOwnerView":true}
        """#.utf8)
        let res = try decoder.decode(CompanionsListResponse.self, from: json)
        XCTAssertEqual(res.items.count, 1)
        XCTAssertEqual(res.items[0].status, .pending)
        XCTAssertTrue(res.isOwnerView)
    }

    /// `displayName`/`avatarEmoji` are nullable server-side
    /// (`accounts.get(r.accountId)?.displayName ?? null`) — a row for an
    /// account with neither set must not fail the whole roster decode.
    func testListItemNullDisplayNameDoesNotFailDecode() throws {
        let json = Data(#"""
        {"items":[{"accountId":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","displayName":null,"avatarEmoji":null,"status":1}],"isOwnerView":false}
        """#.utf8)
        let res = try decoder.decode(CompanionsListResponse.self, from: json)
        XCTAssertEqual(res.items.count, 1)
        XCTAssertNil(res.items[0].displayName)
        XCTAssertNil(res.items[0].avatarEmoji)
        XCTAssertEqual(res.items[0].status, .accepted)
    }

    // MARK: - /companions/candidates

    /// Verbatim task-10 step 1 response.
    func testCandidatesNextCursorNull() throws {
        let json = Data(#"""
        {"items":[{"id":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","displayName":"Companion B","avatarEmoji":"🚗","profileLevel":1}],"nextCursor":null}
        """#.utf8)
        let res = try decoder.decode(CompanionsCandidatesResponse.self, from: json)
        XCTAssertEqual(res.items.count, 1)
        // The server aliases the account id column as "id", not "accountId" —
        // this assertion is the load-bearing check that CompanionCandidate's
        // CodingKeys bridges it back correctly.
        XCTAssertEqual(res.items[0].accountId, companionB)
        XCTAssertEqual(res.items[0].displayName, "Companion B")
        XCTAssertEqual(res.items[0].avatarEmoji, "🚗")
        XCTAssertEqual(res.items[0].profileLevel, 1)
        XCTAssertNil(res.nextCursor)
    }

    /// The live scenario only ever seeded one candidate (< the 30-row page
    /// size), so no recorded response has a non-null `nextCursor`. The
    /// cursor value here is not invented junk: it's
    /// `CompanionsService.encodeCandidatesCursor("Companion B", "1efcd7ab-...")`
    /// (`base64url("Companion B|1efcd7ab-cd57-414e-a3ae-d5ed996991f3")`)
    /// computed by hand from the real algorithm in `companions.service.ts`
    /// against the real seeded account — this test only needs to confirm the
    /// DTO carries a present cursor through untouched, which it does either way.
    func testCandidatesNextCursorPresent() throws {
        let cursor = "Q29tcGFuaW9uIEJ8MWVmY2Q3YWItY2Q1Ny00MTRlLWEzYWUtZDVlZDk5Njk5MWYz"
        let json = Data(#"""
        {"items":[{"id":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","displayName":"Companion B","avatarEmoji":"🚗","profileLevel":1}],"nextCursor":"\#(cursor)"}
        """#.utf8)
        let res = try decoder.decode(CompanionsCandidatesResponse.self, from: json)
        XCTAssertEqual(res.nextCursor, cursor)
    }

    /// `display_name` is a nullable column server-side (the SQL explicitly
    /// `COALESCE`s it) — same null-safety check as `list`, for candidates.
    func testCandidateNullDisplayNameDoesNotFailDecode() throws {
        let json = Data(#"""
        {"items":[{"id":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","displayName":null,"avatarEmoji":null,"profileLevel":1}],"nextCursor":null}
        """#.utf8)
        let res = try decoder.decode(CompanionsCandidatesResponse.self, from: json)
        XCTAssertNil(res.items[0].displayName)
    }

    // MARK: - /companions/invite-preview

    /// Verbatim task-10 step 4 response. The report explicitly checks the
    /// payload key set is exactly these 5 keys (driver, startDate, distance,
    /// duration, region) — no trip id, polyline, photos, or stats.
    func testInvitePreviewExactFiveFields() throws {
        let json = Data(#"""
        {"driver":{"accountId":"a1db2427-2a15-4496-9dd5-efc29edea5f8","displayName":"Driver A","avatarEmoji":"🏎️"},"startDate":"2026-08-10T18:19:21.136Z","distance":42.5,"duration":3600,"region":"Test Region"}
        """#.utf8)

        // Sanity-check the FIXTURE itself carries exactly 5 top-level keys —
        // this is what task-10 step 4 verified against the live server.
        let raw = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        XCTAssertEqual(Set(raw.keys), ["driver", "startDate", "distance", "duration", "region"])

        let preview = try decoder.decode(CompanionInvitePreview.self, from: json)
        XCTAssertEqual(preview.driver?.accountId, driverA)
        XCTAssertEqual(preview.driver?.displayName, "Driver A")
        XCTAssertEqual(preview.driver?.avatarEmoji, "🏎️")
        XCTAssertEqual(preview.startDate.timeIntervalSince1970,
                        ISODate.parse("2026-08-10T18:19:21.136Z")!.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(preview.distance, 42.5)
        XCTAssertEqual(preview.duration, 3600)
        XCTAssertEqual(preview.region, "Test Region")
    }

    /// `driver: null` — the account-lookup miss branch
    /// (`CompanionsService.invitePreview`'s `driver ? {...} : null`).
    func testInvitePreviewNullDriverDoesNotFailDecode() throws {
        let json = Data(#"""
        {"driver":null,"startDate":"2026-08-10T18:19:21.136Z","distance":42.5,"duration":3600,"region":"Test Region"}
        """#.utf8)
        let preview = try decoder.decode(CompanionInvitePreview.self, from: json)
        XCTAssertNil(preview.driver)
    }

    /// `trip.drivingTime` is `integer, nullable: true` on the backend
    /// (`trip.entity.ts`) and `invitePreview()` sends it with NO
    /// coalescing (`duration: trip.drivingTime`) — a trip whose driving
    /// time was never computed (old row predating the column, or a trip
    /// still mid-recording) sends `"duration": null`. This is the one
    /// screen a pending invitee can see before accepting, so failing to
    /// decode this response is a hard stop for them, not a degraded
    /// experience. Fails to compile/decode if `duration` regresses back to
    /// a non-optional `Double`.
    func testInvitePreviewNullDurationDoesNotFailDecode() throws {
        let json = Data(#"""
        {"driver":{"accountId":"a1db2427-2a15-4496-9dd5-efc29edea5f8","displayName":"Driver A","avatarEmoji":"🏎️"},"startDate":"2026-08-10T18:19:21.136Z","distance":42.5,"duration":null,"region":"Test Region"}
        """#.utf8)
        let preview = try decoder.decode(CompanionInvitePreview.self, from: json)
        XCTAssertNil(preview.duration)
        // The UI-facing formatter must omit the line, not print "0 мин"/"0 min".
        XCTAssertNil(preview.formattedDurationHuman(.en))
        XCTAssertNil(preview.formattedDurationHuman(.ru))
    }

    // MARK: - /companions/my-trips (reuses SocialFeedTrip)

    /// task-10 step 8's response body was truncated ("...") in the report
    /// for both `author` and the trip object, so this fixture fills the
    /// fields `SocialFeedTrip` requires but the report elided with values
    /// that are either independently confirmed real (id / author.id /
    /// author.displayName / title / distance / drivingTime / region — all
    /// verbatim from step 8; author.avatarEmoji "🏎️" and startDate from step
    /// 4's `invite-preview`, same account/trip; `duration: 0` from the
    /// report's own "Наблюдения" note on this exact response) or the
    /// obvious zero/empty defaults for a trip acceptance-tested with no
    /// reactions, comments, badges, or photos yet (photoCount,
    /// reactionCount, reactionBreakdown, badgeIds). The point under test is
    /// narrower than re-verifying `SocialFeedTrip` end-to-end: it's that
    /// `CompanionsMyTripsResponse.items` decodes AS `SocialFeedTrip` at all,
    /// with no parallel type — reusing this real data is what keeps that
    /// meaningful.
    func testMyTripsItemDecodesAsSocialFeedTrip() throws {
        let json = Data(#"""
        {"items":[{
            "id":"9c29078a-3b90-4a48-8469-206f4d641912",
            "author":{"id":"a1db2427-2a15-4496-9dd5-efc29edea5f8","displayName":"Driver A","avatarEmoji":"🏎️","profileLevel":1},
            "title":"Acceptance test private trip",
            "startDate":"2026-08-10T18:19:21.136Z",
            "distance":42.5,
            "duration":0,
            "drivingTime":3600,
            "region":"Test Region",
            "photoCount":0,
            "reactionCount":0,
            "reactionBreakdown":[],
            "badgeIds":[]
        }],"nextCursor":null}
        """#.utf8)
        let res = try decoder.decode(CompanionsMyTripsResponse.self, from: json)
        XCTAssertEqual(res.items.count, 1)
        let trip = res.items[0]
        XCTAssertEqual(trip.id, tripId)
        XCTAssertEqual(trip.author.id, driverA)
        XCTAssertEqual(trip.author.displayName, "Driver A")
        XCTAssertEqual(trip.title, "Acceptance test private trip")
        XCTAssertEqual(trip.distance, 42.5)
        XCTAssertEqual(trip.duration, 0)
        XCTAssertEqual(trip.drivingTime, 3600)
        XCTAssertEqual(trip.region, "Test Region")
        XCTAssertNil(res.nextCursor)
    }

    // MARK: - Mutation responses

    /// Verbatim task-10 step 2 response.
    func testInviteResponseDecodes() throws {
        let json = Data(#"""
        {"companion":{"accountId":"1efcd7ab-cd57-414e-a3ae-d5ed996991f3","status":0}}
        """#.utf8)
        let res = try decoder.decode(CompanionsInviteResponse.self, from: json)
        XCTAssertEqual(res.companion.accountId, companionB)
        XCTAssertEqual(res.companion.status, .pending)
    }

    /// Verbatim task-10 step 6 response.
    func testRespondResponseDecodes() throws {
        let json = Data(#"{"status":1}"#.utf8)
        let res = try decoder.decode(CompanionsRespondResponse.self, from: json)
        XCTAssertEqual(res.status, .accepted)
    }

    /// Verbatim task-10 step 12.5 response.
    func testRemoveResponseDecodes() throws {
        let json = Data(#"{"ok":true}"#.utf8)
        let res = try decoder.decode(CompanionsRemoveResponse.self, from: json)
        XCTAssertTrue(res.ok)
    }

    // MARK: - `isPrivate` (Task 5 review finding: Trip(social:) was hardcoding
    // `false`, so a genuinely private «Со мной» trip rendered — and offered
    // Share/reactions/comments — as if it were public. Fixed by adding this
    // field to the DTO and threading it through `Trip(social:)`.)

    /// Verbatim `testMyTripsItemDecodesAsSocialFeedTrip` shape, minus
    /// `isPrivate` — an older server (or any response recorded before this
    /// field shipped) must still decode, and the resulting trip must read as
    /// public, not crash or silently become unrepresentable.
    func testFeedTripWithoutIsPrivateKeyDecodesAsPublic() throws {
        let json = Data(#"""
        {"items":[{
            "id":"9c29078a-3b90-4a48-8469-206f4d641912",
            "author":{"id":"a1db2427-2a15-4496-9dd5-efc29edea5f8","displayName":"Driver A","avatarEmoji":"🏎️","profileLevel":1},
            "title":"No isPrivate key at all",
            "startDate":"2026-08-10T18:19:21.136Z",
            "distance":42.5,
            "duration":0,
            "photoCount":0,
            "reactionCount":0,
            "reactionBreakdown":[],
            "badgeIds":[]
        }],"nextCursor":null}
        """#.utf8)
        let res = try decoder.decode(CompanionsMyTripsResponse.self, from: json)
        let dto = res.items[0]
        XCTAssertNil(dto.isPrivate)
        XCTAssertFalse(Trip(social: dto).isPrivate, "an absent isPrivate key must read as public, not private")
    }

    /// The other half: a companion trip the server explicitly marks private
    /// (the whole point of an invite — a public trip needs no invite to see)
    /// must decode as private and produce a private `Trip`.
    func testFeedTripWithIsPrivateTrueProducesAPrivateTrip() throws {
        let json = Data(#"""
        {"items":[{
            "id":"9c29078a-3b90-4a48-8469-206f4d641912",
            "author":{"id":"a1db2427-2a15-4496-9dd5-efc29edea5f8","displayName":"Driver A","avatarEmoji":"🏎️","profileLevel":1},
            "title":"Genuinely private companion trip",
            "startDate":"2026-08-10T18:19:21.136Z",
            "distance":42.5,
            "duration":0,
            "isPrivate":true,
            "photoCount":0,
            "reactionCount":0,
            "reactionBreakdown":[],
            "badgeIds":[]
        }],"nextCursor":null}
        """#.utf8)
        let res = try decoder.decode(CompanionsMyTripsResponse.self, from: json)
        let dto = res.items[0]
        XCTAssertEqual(dto.isPrivate, true)
        XCTAssertTrue(Trip(social: dto).isPrivate, "isPrivate:true must survive into the Trip the detail screen renders")
    }
}
