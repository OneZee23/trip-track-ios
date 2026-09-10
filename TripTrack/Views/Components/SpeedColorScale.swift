import SwiftUI
import UIKit

/// Single source of truth for the speed→colour scale used to paint route
/// polylines (`RouteMapView`, `PosterRouteCanvas`, the speed chart in
/// `TripDetailSections`). Keeping the thresholds in one place means no two
/// renderers can disagree about which colour a speed is.
///
/// Thresholds (km/h): 0–50 green · 50–90 yellow · 90–110 orange · 110+ red.
/// They **paint**, they never get printed — so they stay metric, like every
/// other threshold in the app.
///
/// A `legendRows()` used to live here, building "0–50 / 50–90 / 90–110 / 110+"
/// labels for an on-map `SpeedLegendView` that no longer exists (0.6.7 removed
/// both). If a legend ever comes back: for miles it needs a **redrawn scale**
/// of 30/60/70, not these numbers divided by 1.609 into 31/56/68. Printing
/// these thresholds under an "mph" header would be a lie.
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
}
