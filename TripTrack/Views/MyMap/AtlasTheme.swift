import SwiftUI
import UIKit

/// Поверхности «Атласа» и «Мест».
///
/// **Нейтральные поверхности здесь — ТЕ ЖЕ, что у «Ленты» и «Я»**
/// (`AppTheme.Colors`), и это не совпадение чисел, а правило. До 26 сентября
/// у этих двух вкладок была СВОЯ тёмная палитра из HTML-макета: фон теплее на
/// 24 единицы, карточка светлее на 18, а вторичный текст — на 105, то есть
/// вчетверо заметнее остального приложения. Владелец на устройстве: «дизайн в
/// атласе и местах очень такой приближенный, отличается от того аккуратного,
/// что у меня в ленте и в Я». Своими остаются только те цвета, которых у
/// приложения нет вовсе: бумага карты, мгла, булавки и терракота «Атласа».
///
/// Светлая половина и раньше совпадала с `AppTheme` с точностью до пары
/// единиц — расходилась ровно тёмная.
enum AtlasTheme {
    /// = `AppTheme.Colors.bg`.
    static let background = adaptive(0xF8F6F2, 0x121214)
    /// = `AppTheme.Colors.text`.
    static let ink = adaptive(0x1E1E23, 0xEBEBEB)
    /// = `AppTheme.Colors.textSecondary`. Именно он и был вчетверо громче.
    static let secondary = adaptive(0x64646E, 0x8C8C8C)
    static let accent = adaptive(0xC8472D, 0xEF8063)
    static let accentSoft = adaptive(0xF6E1D9, 0x432A22)
    static let accentInk = adaptive(0x8A2E1B, 0xF6B09A)
    /// = `AppTheme.Colors.card`.
    static let card = adaptive(0xFFFFFF, 0x1E1E20)
    static let navSurface = adaptive(0xFAF8F4, 0x1E1E20)
    static let navInactive = adaptive(0x64646E, 0x8C8C8C)
    static let progressTrack = adaptive(0xE6DFD4, 0x2A2A2C)
    static let separator = adaptive(0xEAE3D8, 0x2A2A2C)
    static let searchBackground = adaptive(0xECE6DC, 0x2A2A2C)
    /// Нейтральный чип-подпись («частый гость»): тише карточки, но заметнее
    /// фона. Акцентным он читался наградой, которой не является.
    static let chip = adaptive(0xF0EBE3, 0x2A2A2C)
    /// Булавка места ВНЕ выбранного периода: приглушённая, но не прозрачная —
    /// место не перестаёт существовать оттого, что окно его не захватило.
    static let mutedPin = adaptive(0xA0988B, 0x6E6961)
    static let handle = adaptive(0xD3CCC1, 0x61594F)
    static let control = adaptive(0xFFFFFF, 0x1E1E20)
    /// Мгла «Атласа». Она же — бумага карты «Мест», когда плиток Apple нет
    /// (состояние 24 спеки «Места v2»), и рисует её MapKit, а не SwiftUI:
    /// поэтому число живёт в `UIColor`, а `Color` выведен из него. Двух
    /// записей одного цвета быть не должно — они однажды разойдутся.
    static let fogUIColor = adaptiveUIColor(0xEEEEEC, 0x262B36)
    static let fog = Color(fogUIColor)
    static let fogGrain = adaptive(0x7D8792, 0x7D8792)
    // MARK: Стекло плавающих кнопок (спека §3.2, tokens.json → colors.glass)

    /// Заливка кнопки периода и капсулы кнопок карты. Второй материал
    /// вкладки: стекло — только у того, что лежит ПОВЕРХ карты, всё
    /// остальное (шторка, карточки, диалоги) идёт на обычном фоне
    /// приложения (принцип 2).
    static let glass = adaptiveRGBA(0xFAF8F4, 0.94, 0x1E2125, 0.92)
    /// Волосяная обводка стекла и разделитель внутри капсулы.
    static let glassBorder = adaptiveRGBA(0x000000, 0.06, 0xFFFFFF, 0.08)
    /// Скрим модальных шторок и диалогов.
    static let scrim = adaptiveRGBA(0x0C0E10, 0.38, 0x000000, 0.55)

    static let sheetRadius: CGFloat = 28
    /// 16, как умолчание `surfaceCard()` в «Ленте» и «Я»: восемнадцать из
    /// HTML-макета делали карточки заметно круглее соседних вкладок.
    static let cardRadius: CGFloat = 16
    static let statRadius: CGFloat = 16
    static let sideInset: CGFloat = 16
    static let controlSize: CGFloat = 44

    private static func adaptiveRGBA(_ light: UInt32, _ lightAlpha: CGFloat,
                                     _ dark: UInt32, _ darkAlpha: CGFloat) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(adaptiveUIColor(light, dark))
    }

    private static func adaptiveUIColor(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

extension View {
    /// Стекло плавающей кнопки над картой: заливка, волосяная обводка и
    /// мягкая тень одними числами (спека §3.2). Второй материал вкладки, и
    /// он положен ТОЛЬКО тому, что лежит поверх карты.
    func atlasGlass<S: InsettableShape>(_ shape: S) -> some View {
        self.background(shape.fill(AtlasTheme.glass))
            .overlay(shape.strokeBorder(AtlasTheme.glassBorder, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }

    /// Заголовок секции целиком — ровно тот же, что `ProfileSectionLabel`
    /// на экране «Я»: чернила, полужирный, обычный регистр. Прописные и
    /// вторичный цвет ушли вместе с HTML-макетом: они и делали «Атлас» и
    /// «Места» непохожими на соседние вкладки.
    func atlasSectionStyle() -> some View {
        self.font(AppType.section)
            .tracking(AppType.sectionTracking)
            .foregroundStyle(AtlasTheme.ink)
    }
}
