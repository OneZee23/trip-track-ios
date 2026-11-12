import MapKit

final class HiddenHandleAnnotation: MKPointAnnotation {
    var handle: HiddenHandle

    init(handle: HiddenHandle) {
        self.handle = handle
        super.init()
        coordinate = handle.coordinate
    }
}
