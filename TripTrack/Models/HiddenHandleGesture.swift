import CoreLocation
import Foundation

struct HiddenHandleGesture {
    enum Phase: Equatable {
        case began
        case changed
        case ended
        case cancelled
    }

    let phase: Phase
    let handleID: String
    let coordinate: CLLocationCoordinate2D
    let snappedIndex: Int
    let fingerPoint: CGPoint
    let handlePoint: CGPoint
    let metresPerPoint: Double
    let outsideEndpoint: Bool
}
