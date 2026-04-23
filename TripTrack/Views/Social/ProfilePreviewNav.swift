import SwiftUI
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// Enum-keyed destinations for the profile-preview NavigationStack path.
/// Using a path instead of chained `.navigationDestination(isPresented:)`
/// lets us enforce a depth cap, which dodges a SwiftUI bug that lights up
/// at stack depth 4+: during pop animation at deep levels the hidden nav
/// bar flashes a default "← Back" for ~1 sec. User-facing cap of 3 pushes
/// keeps us below the threshold while preserving realistic flows
/// (Me → Followers → Daniil → Daniil's Followers).
enum ProfilePreviewDest: Hashable {
    case profile(UUID, SocialAuthor?)
    case followList(UUID, FollowListMode)
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
