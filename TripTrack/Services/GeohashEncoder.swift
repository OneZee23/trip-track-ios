import CoreLocation

enum GeohashEncoder {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Encode a coordinate to a geohash string of given precision (1-12)
    static func encode(latitude: Double, longitude: Double, precision: Int = 6) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bits = 0
        var currentChar = 0
        var isLon = true

        while hash.count < precision {
            if isLon {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    currentChar = (currentChar << 1) | 1
                    lonRange.0 = mid
                } else {
                    currentChar = currentChar << 1
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    currentChar = (currentChar << 1) | 1
                    latRange.0 = mid
                } else {
                    currentChar = currentChar << 1
                    latRange.1 = mid
                }
            }
            isLon.toggle()
            bits += 1

            if bits == 5 {
                hash.append(base32[currentChar])
                bits = 0
                currentChar = 0
            }
        }
        return hash
    }

    /// Decode a geohash to its bounding box
    static func decode(_ hash: String) -> (lat: ClosedRange<Double>, lon: ClosedRange<Double>) {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isLon = true

        for char in hash.lowercased() {
            guard let idx = base32.firstIndex(of: char) else { continue }
            let charValue = base32.distance(from: base32.startIndex, to: idx)

            for i in stride(from: 4, through: 0, by: -1) {
                let bit = (charValue >> i) & 1
                if isLon {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if bit == 1 { lonRange.0 = mid } else { lonRange.1 = mid }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if bit == 1 { latRange.0 = mid } else { latRange.1 = mid }
                }
                isLon.toggle()
            }
        }

        return (latRange.0...latRange.1, lonRange.0...lonRange.1)
    }

    /// Get the center coordinate of a geohash cell
    static func centerCoordinate(of hash: String) -> CLLocationCoordinate2D {
        let box = decode(hash)
        return CLLocationCoordinate2D(
            latitude: (box.lat.lowerBound + box.lat.upperBound) / 2,
            longitude: (box.lon.lowerBound + box.lon.upperBound) / 2
        )
    }

    /// Get the 8 neighboring geohash cells
    static func neighbors(of hash: String) -> [String] {
        let center = centerCoordinate(of: hash)
        let box = decode(hash)
        let latDelta = box.lat.upperBound - box.lat.lowerBound
        let lonDelta = box.lon.upperBound - box.lon.lowerBound

        let offsets: [(Double, Double)] = [
            (-latDelta, -lonDelta), (-latDelta, 0), (-latDelta, lonDelta),
            (0, -lonDelta),                          (0, lonDelta),
            (latDelta, -lonDelta),  (latDelta, 0),  (latDelta, lonDelta)
        ]

        return offsets.map { offset in
            encode(
                latitude: center.latitude + offset.0,
                longitude: center.longitude + offset.1,
                precision: hash.count
            )
        }
    }
}
