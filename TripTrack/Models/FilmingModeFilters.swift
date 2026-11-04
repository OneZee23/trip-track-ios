import CoreLocation

enum FilmingModeFilters {
    static func visiblePhotos(
        _ photos: [TripPhoto],
        points: [TrackPoint],
        resolution: HiddenPartsResolution,
        homeZone: Zone?
    ) -> [TripPhoto] {
        photos.filter {
            !HiddenPartsResolver.photoIsHidden(
                capturedAt: $0.capturedAt, coordinate: $0.exifCoordinate,
                resolution: resolution, points: points, zone: homeZone)
        }
    }

    static func hidesPlace(
        _ coordinate: CLLocationCoordinate2D,
        trips: [Trip],
        homeZone: Zone?,
        defaultEdgeMetres: Int?
    ) -> Bool {
        if let homeZone,
           PrivacyZone.hides(coordinate, centre: homeZone.centre, radius: homeZone.radius) {
            return true
        }
        for trip in trips where !trip.trackPoints.isEmpty {
            let parts = trip.hiddenParts ?? TripHiddenParts()
            let resolution = HiddenPartsResolver.resolve(
                points: trip.trackPoints,
                recordingBreaks: trip.recordingBreaks,
                startMetres: parts.startMetres ?? defaultEdgeMetres ?? 0,
                endMetres: parts.endMetres ?? defaultEdgeMetres ?? 0,
                sections: parts.sections,
                zone: homeZone
            )
            if resolution.hiddenRuns.flatMap({ $0 }).contains(where: {
                GeometryUtils.haversineDistance(coordinate, $0.coordinate) <= 75
            }) { return true }
        }
        return false
    }

    static func keepsLocationDot(isFilming: Bool, isRecordingScreen: Bool) -> Bool {
        !isFilming || isRecordingScreen
    }
}
