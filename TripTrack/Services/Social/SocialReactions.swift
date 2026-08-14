import Foundation

/// Rebuilds of a feed item, shared by every surface that holds trips of its
/// own. `SocialFeedTrip` is an all-`let` DTO, so an optimistic bump has to go
/// through the memberwise init — and there is more than one holder now: the
/// feed store owns a paged array, `PublicProfileView` owns the ten trips of
/// the profile it is showing. One copy of the rebuild, or the two drift.
extension SocialFeedTrip {
    /// Rebuild with a new comment count.
    func with(commentCount: Int) -> SocialFeedTrip {
        SocialFeedTrip(
            id: id, author: author, title: title, description: description,
            startDate: startDate, endDate: endDate,
            distance: distance, duration: duration,
            maxSpeed: maxSpeed, elevation: elevation,
            maxAltitude: maxAltitude, drivingTime: drivingTime, stoppedTime: stoppedTime,
            region: region, isPrivate: isPrivate,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount, reactionBreakdown: reactionBreakdown,
            myReaction: myReaction, badgeIds: badgeIds,
            commentCountRaw: commentCount
        )
    }

    func with(reactionCount: Int, myReaction: String?) -> SocialFeedTrip {
        // Rebuild breakdown locally to reflect optimistic toggle:
        // decrement previous myReaction bucket, increment new one.
        var breakdown = reactionBreakdown.reduce(into: [String: Int]()) { $0[$1.emoji] = $1.count }
        if let old = self.myReaction {
            breakdown[old, default: 1] -= 1
            if (breakdown[old] ?? 0) <= 0 { breakdown.removeValue(forKey: old) }
        }
        if let new = myReaction {
            breakdown[new, default: 0] += 1
        }
        let updated = breakdown
            .map { ReactionTally(emoji: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        return SocialFeedTrip(
            id: id, author: author, title: title, description: description,
            startDate: startDate, endDate: endDate,
            distance: distance, duration: duration,
            maxSpeed: maxSpeed, elevation: elevation,
            maxAltitude: maxAltitude, drivingTime: drivingTime, stoppedTime: stoppedTime,
            region: region, isPrivate: isPrivate,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount, reactionBreakdown: updated,
            myReaction: myReaction, badgeIds: badgeIds,
            commentCountRaw: commentCountRaw
        )
    }

    /// The card as it must look the instant a tally pill is tapped: same emoji
    /// as mine → the reaction is removed, a different one → mine moves, none
    /// of mine → the total grows by one.
    func togglingReaction(_ emoji: String) -> SocialFeedTrip {
        let wasSameEmoji = myReaction == emoji
        let newCount: Int
        if wasSameEmoji {
            newCount = max(0, reactionCount - 1)
        } else if myReaction != nil {
            newCount = reactionCount
        } else {
            newCount = reactionCount + 1
        }
        return with(reactionCount: newCount, myReaction: wasSameEmoji ? nil : emoji)
    }
}

/// The network half of a reaction tap. Split from the optimistic half above so
/// a caller can flip its own copy first and revert it if this throws.
enum SocialReactions {
    /// `previous` is the RAW stored reaction (a legacy ❤️ stays ❤️ here) —
    /// the same-emoji comparison is what turns a tap into an unreact, and
    /// canonicalising first would silently REPLACE the old reaction instead
    /// of removing it.
    static func send(tripId: UUID, previous: String?, emoji: String) async throws {
        if previous == emoji {
            let _: SocialReactResponse = try await APIClient.shared.post(
                APIEndpoint.socialUnreact, body: SocialUnreactRequest(tripId: tripId))
        } else {
            let _: SocialReactResponse = try await APIClient.shared.post(
                APIEndpoint.socialReact, body: SocialReactRequest(tripId: tripId, emoji: emoji))
        }
    }
}
