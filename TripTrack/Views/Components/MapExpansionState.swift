import SwiftUI

/// Hero → fullscreen uses the same map with one resize and a crossfade.
/// The intermediate states keep ownership separate from visual appearance.
enum MapExpansionState: String, Equatable, CaseIterable {
    case collapsed
    case expanding
    case expanded
    case collapsing

    var isPresented: Bool { self != .collapsed }
    /// Target opacity; the fullscreen viewport itself never animates its size.
    var isVisible: Bool { self == .expanded }
    var showsChrome: Bool { self == .expanded }
    var isInteractive: Bool { self == .expanded }
    var heroShowsSnapshot: Bool { self != .collapsed }

    static let duration: Double = 0.2
    static let reducedDuration: Double = 0.15

    static func animation(reduceMotion: Bool) -> Animation {
        .easeOut(duration: settleDelay(reduceMotion: reduceMotion))
    }

    /// Controls appear with the map; there is no moving frame to wait for.
    static func chromeDelay(reduceMotion: Bool) -> Double { 0 }

    /// Describes timing; completion callbacks, never sleeps, drive ownership.
    static func settleDelay(reduceMotion: Bool) -> Double {
        reduceMotion ? reducedDuration : duration
    }
}
