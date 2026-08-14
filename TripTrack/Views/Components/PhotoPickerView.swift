import SwiftUI
import PhotosUI

// TODO(v0.6-defer): Figma 117:587 specs a custom photo-grid sheet (orange
// selection-order badges, «Готово · 3» header) — the system PHPicker ships
// v1; the custom grid is a larger standalone piece.
struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        // Numbered badges instead of anonymous ticks. The picker opens on a
        // library that already contains the photos you added a minute ago,
        // so a tick that means "selected right now" and a photo that is
        // already on the trip look identical — «1» «2» at least says how
        // many this round is about, and in which order they will land.
        config.selection = .ordered
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }
            let group = DispatchGroup()
            var images: [UIImage] = []
            for result in results {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let uiImage = image as? UIImage {
                        DispatchQueue.main.async {
                            images.append(uiImage)
                            group.leave()
                        }
                    } else {
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                self.parent.selectedImages = images
                self.parent.dismiss()
            }
        }
    }
}
