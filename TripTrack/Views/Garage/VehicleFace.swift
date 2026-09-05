import SwiftUI

/// Лицо машины: фотография, если она есть, иначе силуэт.
///
/// Одно место, где принимается это решение, — иначе оно расходится по экранам,
/// как уже было: снимок появился в карточке гаража и в чужом списке, а на
/// профиле осталась старая плита, и человек справедливо спросил, почему тут
/// фотографии нет.
///
/// Две формы, и они не взаимозаменяемы:
///
/// - `.banner` — полоса во всю ширину карточки. Ради неё всё и затевалось:
///   фотография машины в квадратике со сторону пальца не показывает ничего,
///   ради чего её стоило снимать. Высота у полосы ОДНА для всех карточек,
///   включая те, где фотографии нет: разнокалиберные карточки в одном списке
///   читаются как поломка вёрстки, а не как разные машины.
/// - `.thumb` — маленький квадрат для превью на профиле и в шторке выбора, где
///   машина упоминается, а не показывается.
///
/// NB для будущих проверок: в `ImageRenderer` (снимки из тестов) спрайт в
/// маленькой плите выглядит вылезающим за её края. Это артефакт отрисовщика —
/// он теряет внутреннее `clipped()`. На устройстве плита обрезает как надо;
/// гоняться за этим призраком не нужно.
struct VehicleFace: View {
    enum Style {
        /// Полоса 16:9 во всю ширину.
        case banner
        /// Квадрат заданной стороны.
        case thumb(CGFloat)

        /// У полосы своего скругления НЕТ: она идёт во всю ширину карточки,
        /// и её углы обязаны совпадать с углами карточки — а `surfaceCard`
        /// только красит фон и ничего не обрезает. Поэтому обрезает карточка,
        /// а полоса рисуется прямоугольной. Со своими 14 точками она смотрелась
        /// бы приклеенным сверху прямоугольником, из-под углов которого видно
        /// фон карточки.
        var corner: CGFloat {
            switch self {
            case .banner: return 0
            case .thumb(let side): return side >= 56 ? 12 : 10
            }
        }
    }

    /// Откуда брать снимок: своя машина читает файл с диска, чужая — ссылку.
    enum Photo {
        case local(VehiclePhoto?)
        case remote(String?)
        case none

        var isEmpty: Bool {
            switch self {
            case .local(let p): return p == nil
            case .remote(let s): return (s ?? "").isEmpty
            case .none: return true
            }
        }
    }

    let photo: Photo
    let assetName: String?
    let fallbackEmoji: String?
    var style: Style = .banner
    /// Проданная машина показывается приглушённо — как и везде в гараже.
    var dimmed: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var isBanner: Bool {
        if case .banner = style { return true }
        return false
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        content(c)
            .clipShape(RoundedRectangle(cornerRadius: style.corner, style: .continuous))
            .opacity(dimmed ? 0.55 : 1)
    }

    @ViewBuilder
    private func content(_ c: AppTheme.Colors) -> some View {
        switch style {
        case .banner:
            ZStack {
                // Полоса ВСЕГДА закрашена во всю ширину, и закрашена тем же
                // градиентом, что плита спрайта. Первый заход красил её в
                // `cardAlt` и ставил плиту по центру — на светлой теме этот
                // цвет совпадает с фоном страницы, и верх карточки читался
                // дырой, в которой висит наклейка. Теперь плита и есть полоса.
                LinearGradient(
                    colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                face(c, spriteSize: Self.bannerHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.bannerHeight)

        case .thumb(let side):
            // Рамку НЕ навязываем: плита считает свою высоту сама
            // (`plateHeight` = чернила + пятая часть стороны), и квадрат
            // поверх неё её не сжимает, а обрезает — спрайт вылезал за
            // пределы плиты вбок. Фотографии рамка нужна, плите — нет.
            switch photo {
            case .local, .remote:
                // Силуэт лежит ПОД снимком и просвечивает, пока тот грузится
                // или если не доехал вовсе. Раньше на его месте была серая
                // плашка со значком «фотография» — в превью на профиле она
                // читалась как поломка, при том что нарисованная машина у нас
                // есть всегда.
                // Именно НАЛОЖЕНИЕ, а не стопка: `overlay` получает размер
                // от того, на что накладывается, — то есть от силуэта, который
                // считает свою высоту сам. В `ZStack` снимок размера не имеет
                // и растягивает стопку до своих настоящих пропорций: плитка на
                // профиле превращалась в вертикальный кадр во всю карточку.
                VehicleSpritePlate(
                    assetName: assetName,
                    fallbackEmoji: fallbackEmoji,
                    plateSize: side,
                    uniformHeight: true,
                    cornerRadius: style.corner
                )
                .overlay { photoLayer }
            default:
                VehicleSpritePlate(
                    assetName: assetName,
                    fallbackEmoji: fallbackEmoji,
                    plateSize: side,
                    uniformHeight: true,
                    cornerRadius: style.corner
                )
            }
        }
    }

    @ViewBuilder
    private func face(_ c: AppTheme.Colors, spriteSize: CGFloat) -> some View {
        switch photo {
        case .local(let p) where p != nil:
            VehiclePhotoImage(photo: p!, maxSize: maxSize)
        case .remote(let url) where !(url ?? "").isEmpty:
            if let parsed = URL(string: url!) {
                VehiclePhotoImage(source: .remote(url: parsed), maxSize: maxSize)
            }
        default:
            // Силуэт без собственной плиты в режиме полосы: плитой служит сама
            // полоса. В маленьком квадрате плита остаётся — там она и есть
            // фон.
            VehicleSpritePlate(
                assetName: assetName,
                fallbackEmoji: fallbackEmoji,
                plateSize: spriteSize,
                uniformHeight: true,
                cornerRadius: isBanner ? 0 : style.corner,
                // В полосе подложка уже нарисована — своя была бы вторым
                // градиентом поверх первого и проступала бы прямоугольником.
                showsPlate: !isBanner
            )
        }
    }

    /// Ровно та высота, в которой полосу и покажут: просить у декодера больше —
    /// это мегабайты в память на каждую карточку.
    /// Сам снимок, без подложки: её роль играет силуэт под ним.
    @ViewBuilder
    private var photoLayer: some View {
        switch photo {
        case .local(let p) where p != nil:
            VehiclePhotoImage(photo: p!, maxSize: maxSize, placeholder: .transparent)
        case .remote(let url) where !(url ?? "").isEmpty:
            if let parsed = URL(string: url!) {
                VehiclePhotoImage(source: .remote(url: parsed),
                                  maxSize: maxSize, placeholder: .transparent)
            }
        default:
            EmptyView()
        }
    }

    /// В ТОЧКАХ: на пиксели умножит кэш, по масштабу экрана.
    private var maxSize: CGFloat {
        switch style {
        case .banner: return 400
        case .thumb(let side): return side
        }
    }

    /// Одна высота на все карточки гаража — своего и чужого.
    static let bannerHeight: CGFloat = 148
}
