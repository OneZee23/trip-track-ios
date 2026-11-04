import Foundation

struct FilmingModeState: Equatable {
    var manual = false
    var automatic = true
    var isCaptured = false
    var debugForced = false

    var isActive: Bool { debugForced || manual || (automatic && isCaptured) }
}
