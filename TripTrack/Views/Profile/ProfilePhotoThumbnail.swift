import SwiftUI

struct ProfilePhotoThumbnail: View {
    let filename: String
    var maxSize: CGFloat = 140
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(.secondary.opacity(0.12)) }
        }
        .task(id: filename) {
            image = await VehicleImageCache.sized(
                fileURL: ProfilePhotoStore.directory.appendingPathComponent(filename),
                key: VehicleImageCache.localKey(filename, maxSize), maxSize: maxSize)
        }
        .accessibilityHidden(true)
    }
}
