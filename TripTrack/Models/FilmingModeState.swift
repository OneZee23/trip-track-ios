import Foundation

struct FilmingModeState: Equatable {
    var manual = false
    var automatic = true
    var isCaptured = false

    var isActive: Bool { manual || (automatic && isCaptured) }
}
