import Foundation
import CoreLocation

/// Calculates sunrise/sunset times using the standard solar equations.
/// No external dependencies needed.
struct SunCalculator {

    /// Returns true if it's currently "night" (before sunrise or after sunset) at the given coordinate.
    static func isNight(at coordinate: CLLocationCoordinate2D, date: Date = Date()) -> Bool {
        guard let (sunrise, sunset) = sunriseSunset(for: coordinate, date: date) else {
            // Fallback: use 6:00–21:00 as daytime
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 6 || hour >= 21
        }
        return date < sunrise || date > sunset
    }

    /// Returns (sunrise, sunset) for a given coordinate and date, or nil if calculation fails.
    static func sunriseSunset(for coordinate: CLLocationCoordinate2D, date: Date) -> (sunrise: Date, sunset: Date)? {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude

        // Solar noon approximation
        let lngHour = longitude / 15.0

        // Sunrise
        let tRise = dayOfYear + (6.0 - lngHour) / 24.0
        // Sunset
        let tSet = dayOfYear + (18.0 - lngHour) / 24.0

        guard let sunriseTime = sunTime(dayOfYear: tRise, latitude: latitude, longitude: longitude, isSunrise: true, date: date),
              let sunsetTime = sunTime(dayOfYear: tSet, latitude: latitude, longitude: longitude, isSunrise: false, date: date) else {
            return nil
        }

        return (sunriseTime, sunsetTime)
    }

    private static func sunTime(dayOfYear t: Double, latitude: Double, longitude: Double, isSunrise: Bool, date: Date) -> Date? {
        // Sun's mean anomaly
        let M = (0.9856 * t) - 3.289

        // Sun's true longitude
        var L = M + (1.916 * sin(M.radians)) + (0.020 * sin(2 * M.radians)) + 282.634
        L = L.mod360()

        // Right ascension
        var RA = atan(0.91764 * tan(L.radians)).degrees
        RA = RA.mod360()

        let lQuadrant = (floor(L / 90.0)) * 90.0
        let raQuadrant = (floor(RA / 90.0)) * 90.0
        RA = RA + (lQuadrant - raQuadrant)
        RA = RA / 15.0

        let sinDec = 0.39782 * sin(L.radians)
        let cosDec = cos(asin(sinDec))

        // Sun's local hour angle
        let zenith = 90.833 // official zenith with refraction
        let cosH = (cos(zenith.radians) - (sinDec * sin(latitude.radians))) / (cosDec * cos(latitude.radians))

        // No sunrise/sunset (polar regions)
        guard cosH >= -1.0, cosH <= 1.0 else { return nil }

        var H: Double
        if isSunrise {
            H = 360.0 - acos(cosH).degrees
        } else {
            H = acos(cosH).degrees
        }
        H = H / 15.0

        // Local mean time of event
        let lngHour = longitude / 15.0
        let T = H + RA - (0.06571 * t) - 6.622

        var UT = T - lngHour
        UT = UT.mod(24.0)

        // Convert UT hours to Date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let timeZoneOffset = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0
        let localHour = UT + timeZoneOffset
        let seconds = localHour * 3600.0

        return startOfDay.addingTimeInterval(seconds)
    }
}

// MARK: - Math Helpers

private extension Double {
    var radians: Double { self * .pi / 180.0 }
    var degrees: Double { self * 180.0 / .pi }

    func mod360() -> Double {
        var result = self.truncatingRemainder(dividingBy: 360.0)
        if result < 0 { result += 360.0 }
        return result
    }

    func mod(_ value: Double) -> Double {
        var result = self.truncatingRemainder(dividingBy: value)
        if result < 0 { result += value }
        return result
    }
}
