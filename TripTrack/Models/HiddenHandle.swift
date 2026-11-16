import CoreLocation
import Foundation

struct HiddenHandle: Identifiable, Equatable {
    let id: String
    let kind: HiddenHandleKind
    var index: Int
    let allowedIndices: ClosedRange<Int>
    var coordinate: CLLocationCoordinate2D
    let specialIndex: Int?
    let ghost: Bool
    let lifted: Bool
    let pulse: Bool
    let accessibilityLabel: String
    let value: String
    let bubbleTitle: String
    let bubbleCaption: String
    let bubbleVisible: Bool

    static func == (lhs: HiddenHandle, rhs: HiddenHandle) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.index == rhs.index &&
            lhs.allowedIndices == rhs.allowedIndices && lhs.specialIndex == rhs.specialIndex &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude &&
            lhs.ghost == rhs.ghost && lhs.lifted == rhs.lifted && lhs.pulse == rhs.pulse &&
            lhs.accessibilityLabel == rhs.accessibilityLabel && lhs.value == rhs.value &&
            lhs.bubbleTitle == rhs.bubbleTitle && lhs.bubbleCaption == rhs.bubbleCaption &&
            lhs.bubbleVisible == rhs.bubbleVisible
    }
}
