import SwiftUI

/// Снимок машины — свой (файл на диске) или чужой (ссылка).
///
/// Главное свойство: **если копия уже готова, она рисуется в том же кадре**.
/// Всё, что делается задачей, — это как минимум один кадр с заглушкой, а
/// заглушка на месте фотографии и есть тот самый рывок. Поэтому память
/// спрашивается синхронно, в `init`, и только промах уходит в задачу.
///
/// Пока копия нужного размера готовится, показывается уже готовая ДРУГОГО
/// размера, если такая есть: мельче и мягче, но это та же машина, а не серый
/// прямоугольник и не силуэт.
struct VehiclePhotoImage: View {
    enum Source: Equatable {
        case local(filename: String)
        case remote(url: URL)
    }

    /// Что рисовать, пока снимка нет.
    enum Placeholder {
        /// Ровная подложка и значок «фотография» — когда за картинкой пусто.
        case neutral
        /// Ничего: под снимком уже лежит силуэт машины, и он лучше любой
        /// заглушки — не грузится фотография, остаётся машина.
        case transparent
    }

    let source: Source
    /// Наибольшая сторона в точках — ровно та, в которой снимок покажут.
    let maxSize: CGFloat
    var placeholder: Placeholder = .neutral

    @State private var image: UIImage?
    @State private var isExact: Bool
    @State private var missing = false

    init(source: Source, maxSize: CGFloat, placeholder: Placeholder = .neutral) {
        self.source = source
        self.placeholder = placeholder
        // Размер ПРИЖИМАЕТСЯ к общей лестнице. Без этого каждый экран просил
        // свой, чуть отличающийся: 132, 201, 504 — и ключи не совпадали ни с
        // чем, то есть кэш промахивался всегда, а копий в памяти становилось
        // столько же, сколько мест показа.
        self.maxSize = Self.snap(maxSize)
        let exact = VehicleImageCache.cached(Self.key(source, Self.snap(maxSize)))
        _image = State(initialValue: exact ?? Self.anySize(source))
        _isExact = State(initialValue: exact != nil)
    }

    /// Свой снимок по строке из базы — обёртка ради вызывающих, которые
    /// держат `VehiclePhoto`.
    init(photo: VehiclePhoto, maxSize: CGFloat, placeholder: Placeholder = .neutral) {
        self.init(source: .local(filename: photo.filename),
                  maxSize: maxSize, placeholder: placeholder)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if placeholder == .transparent {
                // Ничего не рисуем: под нами силуэт машины, и пусть он и
                // остаётся, если снимок не доехал.
                Color.clear
            } else if missing {
                // Файл исчез, а строка осталась: заглушка честнее пустоты —
                // пустой прямоугольник читается как «грузится» и никогда не
                // загрузится.
                Rectangle().fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            } else {
                Rectangle().fill(Color.gray.opacity(0.12))
            }
        }
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .task(id: taskKey) {
            guard !isExact else { return }
            let loaded = await load()
            if let loaded {
                image = loaded
                isExact = true
            } else if image == nil {
                missing = true
            }
        }
    }

    private var taskKey: String { Self.key(source, maxSize) }

    private func load() async -> UIImage? {
        switch source {
        case .local(let filename):
            let file = VehiclePhotoStore.directory.appendingPathComponent(filename)
            return await VehicleImageCache.sized(
                fileURL: file, key: Self.key(source, maxSize), maxSize: maxSize)
        case .remote(let url):
            return await VehicleImageCache.remote(url, maxSize: maxSize)
        }
    }

    private static func key(_ source: Source, _ maxSize: CGFloat) -> String {
        switch source {
        case .local(let filename): return VehicleImageCache.localKey(filename, maxSize)
        case .remote(let url):     return VehicleImageCache.remoteKey(url, maxSize)
        }
    }

    /// Любая уже готовая копия этого снимка — чтобы показать хоть что-то
    /// осмысленное, пока готовится нужный размер.
    ///
    /// Размеры перечислены явно: `NSCache` не умеет перебирать ключи, а
    /// список их в приложении конечен и короток — плитка, полоса, герой,
    /// полный экран.
    private static func anySize(_ source: Source) -> UIImage? {
        for size in knownSizes.reversed() {
            if let hit = VehicleImageCache.cached(key(source, size)) { return hit }
        }
        return nil
    }

    /// Лестница размеров — В ТОЧКАХ наибольшей стороны. Умножение на масштаб
    /// экрана делает кэш, здесь его быть не должно: раньше часть вызывающих
    /// уже умножала сама, и один и тот же снимок готовился то в 400 точек, то
    /// в 400 пикселей.
    ///
    /// Ступеней ровно четыре, по числу мест показа: маленький тайл превью,
    /// плитка в ленте снимков, карточка-полоса и герой, полный экран.
    static let knownSizes: [CGFloat] = [56, 140, 400, 460]

    /// Ближайшая ступень НЕ МЕНЬШЕ запрошенной: мельче — видно мыло.
    static func snap(_ requested: CGFloat) -> CGFloat {
        knownSizes.first { $0 >= requested } ?? knownSizes[knownSizes.count - 1]
    }
}
