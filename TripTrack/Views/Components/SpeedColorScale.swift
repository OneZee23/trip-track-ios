import SwiftUI
import UIKit

/// Single source of truth for the speed→colour scale used to paint route
/// polylines (`RouteMapView`) **and** the legend drawn over the map
/// (`SpeedLegendView`). Keeping the thresholds in one place means the legend
/// can never drift from what's actually drawn — that drift was the gap the
/// user hit ("the track is red/yellow/green, but which colour is which speed?").
///
/// Thresholds (km/h): 0–50 green · 50–90 yellow · 90–110 orange · 110+ red.
enum SpeedColorScale {
    /// One colour band of the scale. `upperKmh == nil` is the open-ended top.
    struct Band {
        let upperKmh: Double?
        let uiColor: UIColor
        var color: Color { Color(uiColor: uiColor) }
    }

    /// Bands ordered slow→fast. The renderer and the legend both read this.
    static let bands: [Band] = [
        Band(upperKmh: 50,  uiColor: UIColor(red: 0x2E / 255, green: 0xAE / 255, blue: 0x50 / 255, alpha: 0.9)),
        Band(upperKmh: 90,  uiColor: UIColor(red: 0xF5 / 255, green: 0xBE / 255, blue: 0x1E / 255, alpha: 0.9)),
        Band(upperKmh: 110, uiColor: UIColor(red: 0xEB / 255, green: 0x57 / 255, blue: 0x1E / 255, alpha: 0.9)),
        Band(upperKmh: nil, uiColor: UIColor(red: 0xDC / 255, green: 0x3C / 255, blue: 0x32 / 255, alpha: 0.9)),
    ]

    /// Zone index for grouping consecutive same-colour segments (matches the
    /// `< upper` cutoffs of `bands`). Falls through to the last band.
    static func zone(forSpeedMS speedMS: Double) -> Int {
        let kmh = max(0, speedMS) * 3.6
        for (i, band) in bands.enumerated() {
            if let upper = band.upperKmh, kmh < upper { return i }
        }
        return bands.count - 1
    }

    /// Stroke colour for a polyline segment recorded at `speedMS` (m/s).
    static func uiColor(forSpeedMS speedMS: Double) -> UIColor {
        bands[zone(forSpeedMS: speedMS)].uiColor
    }

    /// Legend rows slow→fast: colour swatch + a unit-less km/h range label
    /// ("0–50", "50–90", … "110+"). Numbers are language-neutral; the caller
    /// supplies the "km/h" unit header.
    static func legendRows() -> [(color: Color, range: String)] {
        var rows: [(Color, String)] = []
        var lower = 0
        for band in bands {
            if let upper = band.upperKmh {
                rows.append((band.color, "\(lower)–\(Int(upper))"))
                lower = Int(upper)
            } else {
                rows.append((band.color, "\(lower)+"))
            }
        }
        return rows
    }
}
