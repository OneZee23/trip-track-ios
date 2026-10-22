import SwiftUI

/// The same ground, contact point and photo priority on every garage surface.
struct VehicleStage: View {
    let assetName: String?
    var fallbackEmoji: String = "🚗"
    var style: VehicleCardStyle = .none
    var finish: VehicleFinish = .gloss
    var photo: VehiclePhoto? = nil
    var remotePhoto: URL? = nil
    var width: CGFloat = 300

    private var bodyStyle: String { assetName.map(VehicleAvatar.style(ofAsset:)) ?? VehicleAvatar.defaultStyle }
    private var spriteWidth: CGFloat { width * 0.76 }
    private var spriteHeight: CGFloat { spriteWidth * CGFloat(VehicleSpriteMetrics.canvasAspect) }
    private var ink: (top: Double, bottom: Double) { VehicleSpriteMetrics.inkBounds(style: bodyStyle) }
    private var inkHeight: CGFloat { spriteHeight * CGFloat(ink.bottom - ink.top) }
    private var height: CGFloat { max(width * 0.62, inkHeight + width * 0.22) }
    private var platformY: CGFloat { height - width * 92 / 170 / 2 }
    private var wheelY: CGFloat { height - width * 92 / 170 + width * 85 / 170 * 0.80 }
    private var paintedAsset: String? {
        guard let assetName else { return nil }
        return finish == .matte ? assetName + "_matte" : assetName
    }

    var body: some View {
        Group {
            if let photo {
                VehiclePhotoImage(photo: photo, maxSize: width * 2)
                    .frame(width: width, height: width * 0.60)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else if let remotePhoto {
                VehiclePhotoImage(source: .remote(url: remotePhoto), maxSize: width * 2)
                    .frame(width: width, height: width * 0.60)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                platform
            }
        }
        .accessibilityHidden(true)
    }

    private var platform: some View {
        ZStack(alignment: .topLeading) {
            Image("platform_" + (style == .none ? "asphalt" : String(style.rawValue.dropFirst(5))))
                .resizable().interpolation(.none)
                .frame(width: width, height: width * 92 / 170)
                .position(x: width / 2, y: platformY)
            Image("platform_shadow")
                .resizable().interpolation(.none)
                .frame(width: width * 0.60, height: width * 0.30)
                .position(x: width / 2, y: wheelY - width * 0.09)
            if let paintedAsset {
                Image(paintedAsset)
                    .resizable().interpolation(.none)
                    .frame(width: spriteWidth, height: spriteHeight)
                    .position(
                        x: width / 2,
                        y: wheelY - CGFloat(ink.bottom - 0.5) * spriteHeight)
            } else {
                Text(fallbackEmoji).font(.system(size: width * 0.34))
                    .position(x: width / 2, y: wheelY - width * 0.18)
            }
        }
        .frame(width: width, height: height)
    }
}
