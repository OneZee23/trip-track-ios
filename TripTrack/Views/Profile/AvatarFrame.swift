import SwiftUI

/// Кольцо вокруг аватара — вторая из четырёх косметик «Плюса» (спека §2).
///
/// Рисуется клиентом, как и `ProfileBackground`: на проводе и в базе живёт
/// только строка (`UserSettingsEntity.avatarFrame`, `SettingsSyncPayload
/// .avatarFrame`, `SocialAuthor.avatarFrame`), поэтому подкрутить цвет или
/// добавить вариант можно без миграции и без выкладки сервера.
///
/// `rawValue` менять нельзя никогда — ровно по той же причине, что и у фона.
enum AvatarFrame: String, CaseIterable, Identifiable {
    /// Без рамки. Пустая строка, а не `nil`-кейс: в базе колонка
    /// опциональная, и обе формы «ничего» обязаны сходиться в один ответ.
    case none    = ""
    case gold    = "frame_gold"
    case carbon  = "frame_carbon"
    case neon    = "frame_neon"
    case chrome  = "frame_chrome"
    case laurel  = "frame_laurel"
    case flame   = "frame_flame"

    var id: String { rawValue }

    /// Рамок бесплатных не бывает: сама вещь — платная, и `.none` это её
    /// отсутствие, а не бесплатный вариант.
    var isPlus: Bool { self != .none }

    /// Имя варианта — имя собственное, как «Sunset» у фонов, поэтому мимо
    /// `AppStrings`. Единственное, что переводится, — «без рамки»
    /// (`AppStrings.cosmeticDefaultOption`), и его подставляет экран.
    var displayName: String {
        switch self {
        case .none:   return ""
        case .gold:   return "Gold"
        case .carbon: return "Carbon"
        case .neon:   return "Neon"
        case .chrome: return "Chrome"
        case .laurel: return "Laurel"
        case .flame:  return "Flame"
        }
    }

    /// Цвета кольца по кругу. Один цвет — ровное кольцо, несколько —
    /// угловой градиент.
    var colors: [Color] {
        switch self {
        case .none:
            return []
        case .gold:
            return [Color(red: 0.98, green: 0.84, blue: 0.45),
                    Color(red: 0.76, green: 0.55, blue: 0.16),
                    Color(red: 1.00, green: 0.93, blue: 0.70),
                    Color(red: 0.76, green: 0.55, blue: 0.16)]
        case .chrome:
            return [Color(red: 0.92, green: 0.94, blue: 0.96),
                    Color(red: 0.55, green: 0.59, blue: 0.64),
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                    Color(red: 0.45, green: 0.49, blue: 0.55)]
        case .carbon:
            return [Color(red: 0.22, green: 0.23, blue: 0.26),
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.34, green: 0.36, blue: 0.40),
                    Color(red: 0.08, green: 0.08, blue: 0.10)]
        case .neon:
            return [Color(red: 0.16, green: 0.95, blue: 0.79),
                    Color(red: 0.24, green: 0.55, blue: 0.98),
                    Color(red: 0.16, green: 0.95, blue: 0.79)]
        case .laurel:
            return [Color(red: 0.55, green: 0.72, blue: 0.42),
                    Color(red: 0.24, green: 0.44, blue: 0.26),
                    Color(red: 0.72, green: 0.84, blue: 0.55),
                    Color(red: 0.24, green: 0.44, blue: 0.26)]
        case .flame:
            return [Color(red: 0.99, green: 0.76, blue: 0.28),
                    Color(red: 0.96, green: 0.36, blue: 0.36),
                    Color(red: 0.99, green: 0.76, blue: 0.28)]
        }
    }

    /// Что РИСОВАТЬ, когда «Плюс» кончился — та же дверь и то же правило, что
    /// у `ProfileBackground.effective`: выбор в базе остаётся, кольца на
    /// экране нет.
    func effective(isPlus: Bool) -> AvatarFrame {
        (self.isPlus && !isPlus) ? .none : self
    }

    static func effective(id raw: String?, isPlus: Bool) -> AvatarFrame {
        from(raw).effective(isPlus: isPlus)
    }

    /// Терпимый разбор: незнакомая строка (рамка из будущей версии) — это
    /// «без рамки», а не падение чужого профиля.
    static func from(_ raw: String?) -> AvatarFrame {
        guard let raw, !raw.isEmpty else { return .none }
        return AvatarFrame(rawValue: raw) ?? .none
    }
}

// MARK: - Кольцо

/// Само кольцо. Накладка поверх аватара, а не подложка под ним: аватар бывает
/// и эмодзи на диске, и спрайт, и снимок — общего у них только круглая рамка.
struct AvatarFrameRing: View {
    let frame: AvatarFrame
    var lineWidth: CGFloat = 3

    var body: some View {
        let palette = frame.colors
        if palette.isEmpty {
            Color.clear
        } else {
            Circle()
                .strokeBorder(
                    AngularGradient(colors: palette, center: .center),
                    lineWidth: lineWidth
                )
                // Волосяная тёмная линия внутрь: на светлом аватаре
                // «хромовое» кольцо иначе растворяется в своём же фоне.
                .background(
                    Circle().strokeBorder(.black.opacity(0.10), lineWidth: lineWidth + 1)
                )
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Надеть рамку на круглый аватар. `.none` не рисует ничего и не меняет
    /// раскладку — поэтому звать можно безусловно.
    func avatarFrame(_ frame: AvatarFrame, lineWidth: CGFloat = 3) -> some View {
        overlay { AvatarFrameRing(frame: frame, lineWidth: lineWidth) }
    }
}
