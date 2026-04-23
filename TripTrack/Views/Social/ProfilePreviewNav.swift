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
enum ProfilePreviewDest: Hashable {
    case profile(UUID, SocialAuthor?)
    case followList(UUID, FollowListMode)
    case trip(UUID)
    case socialTrip(SocialFeedTrip)
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
