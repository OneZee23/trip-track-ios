import Foundation
import CoreLocation

struct Trip: Identifiable, Codable {
    let id: UUID
    var startDate: Date
    var endDate: Date?
    var distance: Double // meters
    var maxSpeed: Double // m/s
    var averageSpeed: Double // m/s
    var trackPoints: [TrackPoint]
    var photos: [TripPhoto]

    var title: String?
    var tripDescription: String?
    var fuelUsed: Double
    var elevation: Double
    var region: String?
    var isPrivate: Bool
    var vehicleId: UUID?
    var fuelCurrency: String?
    var previewPolyline: Data?
    var earnedBadgeIds: [String]

    /// Decoded simplified coordinates for feed card route previews.
    var previewCoordinates: [CLLocationCoordinate2D] {
        guard let data = previewPolyline else { return trackPoints.map(\.coordinate) }
        return Self.decodePolyline(data)
    }

    /// Encode an array of coordinates into compact binary data (pairs of Float32).
    static func encodePolyline(_ coords: [CLLocationCoordinate2D]) -> Data {
        var data = Data(capacity: coords.count * 8)
        for coord in coords {
            var lat = Float32(coord.latitude)
            var lon = Float32(coord.longitude)
            data.append(Data(bytes: &lat, count: 4))
            data.append(Data(bytes: &lon, count: 4))
        }
        return data
    }

    /// Decode binary polyline data back into coordinates.
    static func decodePolyline(_ data: Data) -> [CLLocationCoordinate2D] {
        guard data.count >= 8, data.count % 8 == 0 else { return [] }
        let count = data.count / 8
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(count)
        for i in 0..<count {
            let byteOffset = i * 8
            var lat: Float32 = 0
            var lon: Float32 = 0
            _ = withUnsafeMutableBytes(of: &lat) { dest in
                data.copyBytes(to: dest, from: byteOffset..<(byteOffset + 4))
            }
            _ = withUnsafeMutableBytes(of: &lon) { dest in
                data.copyBytes(to: dest, from: (byteOffset + 4)..<(byteOffset + 8))
            }
            coords.append(CLLocationCoordinate2D(latitude: Double(lat), longitude: Double(lon)))
        }
        return coords
    }

    var isActive: Bool {
        endDate == nil
    }

    var duration: TimeInterval {
        let end = endDate ?? Date()
        return end.timeIntervalSince(startDate)
    }

    var distanceKm: Double {
        distance / 1000.0
    }

    var maxSpeedKmh: Double {
        maxSpeed * 3.6
    }

    var averageSpeedKmh: Double {
        averageSpeed * 3.6
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func formattedDurationHuman(_ lang: LanguageManager.Language) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return lang == .ru ? "\(hours) ч \(minutes) мин" : "\(hours) h \(minutes) min"
        }
        if minutes > 0 {
            return lang == .ru ? "\(minutes) мин \(seconds) сек" : "\(minutes) min \(seconds) sec"
        }
        return lang == .ru ? "\(seconds) сек" : "\(seconds) sec"
    }

    init(id: UUID = UUID(), startDate: Date = Date(), endDate: Date? = nil,
         distance: Double = 0, maxSpeed: Double = 0, averageSpeed: Double = 0,
         trackPoints: [TrackPoint] = [], photos: [TripPhoto] = [],
         title: String? = nil, tripDescription: String? = nil,
         fuelUsed: Double = 0, elevation: Double = 0,
         region: String? = nil, isPrivate: Bool = false, vehicleId: UUID? = nil,
         fuelCurrency: String? = nil,
         previewPolyline: Data? = nil, earnedBadgeIds: [String] = []) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.averageSpeed = averageSpeed
        self.trackPoints = trackPoints
        self.photos = photos
        self.title = title
        self.tripDescription = tripDescription
        self.fuelUsed = fuelUsed
        self.elevation = elevation
        self.region = region
        self.isPrivate = isPrivate
        self.vehicleId = vehicleId
        self.fuelCurrency = fuelCurrency
        self.previewPolyline = previewPolyline
        self.earnedBadgeIds = earnedBadgeIds
    }

    var earnedBadges: [Badge] {
        let allBadges = Badge.all
        return earnedBadgeIds.compactMap { id in allBadges.first { $0.id == id } }
    }
}

// Manual Equatable: excludes trackPoints (large array kills SwiftUI diffing)
// and rarely-changing fields (tripDescription, isPrivate, vehicleId, fuelUsed,
// elevation, maxSpeed, averageSpeed) that don't affect feed card rendering.
// Includes previewPolyline because async backfill updates it.
extension Trip: Equatable {
    static func == (lhs: Trip, rhs: Trip) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.distance == rhs.distance &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.region == rhs.region &&
        lhs.photos.count == rhs.photos.count &&
        lhs.previewPolyline == rhs.previewPolyline
    }
}
