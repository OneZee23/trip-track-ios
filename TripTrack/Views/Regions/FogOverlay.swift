import MapKit

final class FogOverlay: NSObject, MKOverlay {
    let revealMask: UIImage?
    let imageMapRect: MKMapRect

    var coordinate: CLLocationCoordinate2D {
        MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate
    }

    var boundingMapRect: MKMapRect { .world }

    init(revealMask: UIImage?, imageMapRect: MKMapRect) {
        self.revealMask = revealMask
        self.imageMapRect = imageMapRect
    }
}
