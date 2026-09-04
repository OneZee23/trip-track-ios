import SwiftUI

/// Снимок машины в списке или на карточке.
///
/// Одно место, где решается, что именно рисуется: уменьшенная копия из кэша,
/// а не оригинал с камеры. Раньше каждая плитка декодировала полный кадр прямо
/// в теле вью, то есть заново на каждую перерисовку.
///
/// Пока копия готовится — ровная подложка, а не пустота: без неё карточка
/// прыгает по высоте на каждой загрузке.
struct VehiclePhotoImage: View {
    let photo: VehiclePhoto
    /// Наибольшая сторона в точках. Ровно та, в которой снимок и покажут.
    let maxSize: CGFloat

    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().clipped()
            } else if missing {
                // Файл исчез, а строка осталась — показываем заглушку, а не
                // пустоту: пустой прямоугольник читается как «грузится» и
                // никогда не грузится.
                Rectangle().fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            } else {
                Rectangle().fill(Color.gray.opacity(0.12))
            }
        }
        .task(id: photo.filename) {
            let loaded = await VehiclePhotoStore.thumbnail(photo, maxSize: maxSize)
            image = loaded
            missing = loaded == nil
        }
    }
}
