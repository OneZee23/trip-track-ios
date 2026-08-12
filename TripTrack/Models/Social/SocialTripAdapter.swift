import Foundation

/// A feed trip, expressed as the app's own `Trip`.
///
/// There used to be two detail screens: `TripDetailView` for a trip in our own
/// database and a separate, thinner one for a trip that arrived from the feed.
/// They drifted, as two screens for one thing always do — the second never grew
/// the elevation and speed charts, its «…» offered only «Поделиться», and a
/// trip of your own opened in it whenever the account id had not been restored
/// from the Keychain yet. One screen, two sources of data.
///
/// What a remote trip cannot carry is the full track: the server sends a
/// simplified preview polyline, not every point. So the route draws without
/// speed colouring and the two charts stay hidden — the detail screen already
/// hides them when there is nothing to plot, which is the same thing it does
/// for an old local trip whose points were trimmed.
extension Trip {
    init(social: SocialFeedTrip) {
        let seconds = Double(social.duration)
        self.init(
            id: social.id,
            startDate: social.startDate,
            endDate: social.endDate ?? social.startDate.addingTimeInterval(seconds),
            distance: social.distance,
            maxSpeed: social.maxSpeed ?? 0,
            // The server sends distance and duration, not the average — and
            // deriving it here keeps one definition of "average speed" in the
            // app instead of two that disagree at the third decimal.
            averageSpeed: seconds > 0 ? social.distance / seconds : 0,
            trackPoints: [],
            photos: [],
            title: social.title,
            tripDescription: social.description,
            elevation: social.elevation ?? 0,
            region: social.region,
            // `nil` (older server, or a feed source that predates this field)
            // reads as public — every trip that could arrive without it was
            // already publicly-visible-to-this-viewer before it existed.
            // A `/companions/my-trips` trip can be genuinely private (that's
            // the whole point of an invite), so this is no longer hardcoded.
            isPrivate: social.isPrivate ?? false,
            // A remote vehicle is a name and an avatar, not a row in our
            // garage — the detail screen reads it from `social.vehicle`.
            vehicleId: nil,
            previewPolyline: social.previewPolyline.flatMap { Data(base64Encoded: $0) },
            earnedBadgeIds: social.badgeIds
        )
    }
}
