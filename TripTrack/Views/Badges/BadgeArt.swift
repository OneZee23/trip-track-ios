import SwiftUI

/// Рисунок значка — пиксельный СИМВОЛ из `Assets.xcassets/Badges`.
///
/// **Контейнер рисует приложение, а не картинка.** До 26 сентября значок
/// приезжал медалью: диск, ободок редкости и тень были вшиты в сам файл, и
/// редкость приходилось перекрашивать прямо в графике. Набор заменён на
/// символы без оправы (владелец, 26 сен) — теперь редкость живёт там, где она
/// и должна: в рамке карточки, в подписи и в заливке плитки, то есть в коде,
/// который знает про `displayRarity` с сервера.
///
/// Поэтому вокруг символа НЕ рисуется ни круга, ни кольца, ни тени. Где нужна
/// подложка — это `BadgeTile` ниже, и она своя, а не часть рисунка.
///
/// Ассет — ВЕКТОР из `svg/` того же набора. Рисунок байт в байт тот же, что в
/// `png/` (так говорит README автора), но растр там 1536×1536: в распакованном
/// виде это девять мегабайт на иконку, а на полке достижений их два десятка
/// разом. Вектор снимает и это, и вопрос чёткости на любом размере — от 32 pt
/// в плитке до 112 на медальоне.
struct BadgeArt: View {
    /// Заработан или ещё нет. Секрета здесь нет нарочно: нераскрытый значок
    /// показывать нельзя вовсе — рисунок и есть ответ, — и вопросительный знак
    /// вместо него рисует сам экран.
    enum State { case unlocked, locked }

    let badge: Badge
    let side: CGFloat
    var state: State = .unlocked

    /// Имя ассета. Папка `Badges` в каталоге даёт пространство имён, чтобы
    /// `first_trip` не столкнулся с чужой картинкой того же имени.
    static func assetName(for id: String) -> String { "Badges/\(id)" }

    var body: some View {
        Image(Self.assetName(for: badge.id))
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            // Незаработанный — обесцвечен и приглушён до 35 % (правило автора
            // набора), а не заменён серым силуэтом: форму видно, и значок
            // узнаётся на полке заранее.
            .saturation(state == .locked ? 0 : 1)
            .opacity(state == .locked ? 0.35 : 1)
    }
}

/// Значок в ПЛИТКЕ — так он стоит там, где иконки мелкие и идут рядами:
/// полоса достижений в «Я» и в ленте.
///
/// Числа из `badges.json` автора набора: плитка 40 pt, скругление 11, символ
/// 32 по центру. Заливка — по редкости, своя для светлой и тёмной темы;
/// шесть пар подобраны так, чтобы символ читался на обеих, поэтому брать
/// вместо них `rarity.color` с прозрачностью нельзя — получится не то.
///
/// Закреплённое достижение плитки НЕ получает: оно и так стоит на своей
/// подложке, и вторая под ним читалась бы рамкой внутри рамки.
struct BadgeTile: View {
    let badge: Badge
    var side: CGFloat = 40
    var state: BadgeArt.State = .unlocked

    @Environment(\.colorScheme) private var scheme

    /// Скругление и символ считаются ОТ стороны, а не вбиты числами: плитка
    /// живёт и в 40 pt, и крупнее, а пропорция у неё одна.
    private var corner: CGFloat { side * 11 / 40 }
    private var symbol: CGFloat { side * 32 / 40 }

    var body: some View {
        BadgeArt(badge: badge, side: symbol, state: state)
            .frame(width: side, height: side)
            .background(
                BadgeTileFill.colour(for: badge.displayRarity, dark: scheme == .dark),
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .opacity(state == .locked ? 0.55 : 1)
    }
}

/// Заливка плитки по редкости. Числа — из `badges.json` набора символов.
///
/// Хекс оставлен литералом нарочно: так строка в коде сверяется с файлом
/// автора глазом, без пересчёта в доли. Своего `Color(hex:)` в приложении нет
/// — и заводить его ради шести цветов значило бы завести седьмой способ
/// объявлять краску.
enum BadgeTileFill {
    static func colour(for rarity: BadgeRarity, dark: Bool) -> Color {
        switch rarity {
        case .common: return rgb(dark ? 0x35393D : 0xF1F2F3)
        case .uncommon: return rgb(dark ? 0x213F2F : 0xE6F5EB)
        case .rare: return rgb(dark ? 0x22384E : 0xE7F1FC)
        case .epic: return rgb(dark ? 0x382D48 : 0xF3EBF9)
        case .legendary: return rgb(dark ? 0x493D21 : 0xFCF4E4)
        case .exclusive: return rgb(dark ? 0x47243C : 0xFBE7F2)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}
