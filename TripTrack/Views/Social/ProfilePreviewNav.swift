import SwiftUI
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// Enum-keyed destinations for every flow that chains social pushes.
/// Using a typed path (vs chained `.navigationDestination(isPresented:)`)
/// lets us enforce a depth cap that dodges a SwiftUI bug at stack depth 4+
/// where the hidden nav bar flashes a default "← Back" for ~1 sec during
/// pop animations. Name is historical — `.trip`/`.socialTrip` were added so
/// Feed's main stack could unify trip + profile pushes under one path
/// (mixing `.navigationDestination(isPresented:)` with a typed
/// `NavigationStack(path:)` made isPresented-pushed views evaporate when
/// the typed path mutated).
/// Where a trip detail should land when it opens.
enum TripFocus: Hashable {
    /// Top of the screen — the poster. Default for a plain card tap.
    case top
    /// The discussion block, for taps on a comment affordance.
    case comments
    /// One specific comment, which also gets highlighted on arrival — the
    /// inbox uses this so "X commented …" lands you on the actual sentence.
    case comment(UUID)
}

/// Payload for the `.openTripDetail` → `.navigateToTrip` handoff when the
/// deep link targets something INSIDE the trip. Senders that only know a
/// trip id still post a bare `UUID`; both observers accept either.
struct TripDeepLink {
    let tripId: UUID
    var focus: TripFocus = .top
}

enum ProfilePreviewDest: Hashable {
    case profile(UUID, SocialAuthor?)
    case followList(UUID, FollowListMode)
    case trip(UUID, focus: TripFocus)
    case socialTrip(SocialFeedTrip, focus: TripFocus)

    /// Plain-open shorthands — every existing `.trip(id)` / `.socialTrip(t)`
    /// call site keeps working and means "open at the top".
    static func trip(_ id: UUID) -> Self { .trip(id, focus: .top) }
    static func socialTrip(_ trip: SocialFeedTrip) -> Self {
        .socialTrip(trip, focus: .top)
    }
}

extension Array where Element == ProfilePreviewDest {
    /// Maximum path depth before further pushes replace the top entry
    /// instead of stacking deeper.
    static let previewDepthCap = 3

    /// Push with replacement: once we're at the cap, drop the deepest
    /// entry before appending so total depth stays bounded.
    mutating func cappedAppend(_ dest: ProfilePreviewDest) {
        let before = count
        if count >= Self.previewDepthCap {
            removeLast()
        }
        append(dest)
        let after = count
        let descr = String(describing: dest)
        navLog.debug("cappedAppend depth \(before)→\(after) dest=\(descr, privacy: .public)")
    }
}
