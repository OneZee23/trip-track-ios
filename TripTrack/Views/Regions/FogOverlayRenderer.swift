import MapKit

final class FogOverlayRenderer: MKOverlayRenderer {
    var isDark: Bool = true

    private var fogColor: UIColor {
        isDark
            ? UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 0.88)
            : UIColor(red: 220/255, green: 220/255, blue: 225/255, alpha: 0.85)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let fog = overlay as? FogOverlay else { return }

        let tileRect = rect(for: mapRect)

        // 1. Fill entire tile with fog
        context.setFillColor(fogColor.cgColor)
        context.fill(tileRect)

        // 2. If tile intersects the reveal mask area, stamp the mask to erase fog
        guard let mask = fog.revealMask?.cgImage,
              mapRect.intersects(fog.imageMapRect) else { return }

        let imageDrawRect = rect(for: fog.imageMapRect)

        context.saveGState()
        context.setBlendMode(.destinationOut)

        context.translateBy(x: 0, y: imageDrawRect.origin.y + imageDrawRect.height)
        context.scaleBy(x: 1, y: -1)
        let flippedRect = CGRect(
            x: imageDrawRect.origin.x,
            y: 0,
            width: imageDrawRect.width,
            height: imageDrawRect.height
        )
        context.draw(mask, in: flippedRect)
        context.restoreGState()
    }
}
