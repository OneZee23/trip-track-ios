import SwiftUI

struct ProfilePhotoThumbnail: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(.secondary.opacity(0.12)) }
        }
        .task(id: filename) {
            image = await VehicleImageCache.sized(
                fileURL: ProfilePhotoStore.directory.appendingPathComponent(filename),
                key: VehicleImageCache.localKey(filename, 140), maxSize: 140)
        }
        .accessibilityHidden(true)
    }
}
