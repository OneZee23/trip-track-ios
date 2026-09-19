import SwiftUI

/// Фон карточки машины в гараже — третья из четырёх косметик «Плюса».
///
/// Восемь вариантов, все платные; `.none` — обычная карточка, какой она была
/// до 0.8.0. Хранится строкой в `VehicleEntity.cardStyle` и едет полем
/// `VehicleSyncPayload.cardStyle` / `PublicVehicle.cardStyle`, поэтому
/// `rawValue` менять нельзя никогда.
///
/// Рисуется НАКЛАДКОЙ на заливку карточки, а не заменой `surfaceCard`: карточка
/// остаётся той же карточкой во всех темах и со всеми своими состояниями
/// (основная машина, проданная), фон лишь красит её.
enum VehicleCardStyle: String, CaseIterable, Identifiable {
    case none       = ""
    case carbon     = "card_carbon"
    case gold       = "card_gold"
    case neon       = "card_neon"
    case racing     = "card_racing"
    case chrome     = "card_chrome"
    case matte      = "card_matte"
    case camo       = "card_camo"
    case sunset     = "card_sunset"

    var id: String { rawValue }

    var isPlus: Bool { self != .none }

    /// Имя собственное, как у фонов профиля — мимо `AppStrings`.
    var displayName: String {
        switch self {
        case .none:   return ""
        case .carbon: return "Carbon"
        case .gold:   return "Gold"
        case .neon:   return "Neon"
        case .racing: return "Racing"
        case .chrome: return "Chrome"
        case .matte:  return "Matte"
        case .camo:   return "Camo"
        case .sunset: return "Sunset"
        }
    }

    /// Два стопа градиента. Прозрачность держится низкой нарочно: под фоном
    /// лежит `surfaceCard`, а поверх — имя, цифры и полоса опыта, и карточка
    /// обязана оставаться читаемой в обеих темах.
    var colors: [Color] {
        switch self {
        case .none:
            return []
        case .carbon:
            return [Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.38),
                    Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.28)]
        case .gold:
            return [Color(red: 0.95, green: 0.80, blue: 0.40).opacity(0.34),
                    Color(red: 0.60, green: 0.42, blue: 0.12).opacity(0.22)]
        case .neon:
            return [Color(red: 0.16, green: 0.86, blue: 0.78).opacity(0.30),
                    Color(red: 0.45, green: 0.22, blue: 0.86).opacity(0.24)]
        case .racing:
            return [Color(red: 0.85, green: 0.16, blue: 0.16).opacity(0.28),
                    Color(red: 0.24, green: 0.05, blue: 0.08).opacity(0.20)]
        case .chrome:
            return [Color(red: 0.86, green: 0.88, blue: 0.91).opacity(0.30),
                    Color(red: 0.45, green: 0.49, blue: 0.55).opacity(0.22)]
        case .matte:
            return [Color(red: 0.34, green: 0.36, blue: 0.38).opacity(0.26),
                    Color(red: 0.22, green: 0.23, blue: 0.25).opacity(0.24)]
        case .camo:
            return [Color(red: 0.42, green: 0.46, blue: 0.29).opacity(0.32),
                    Color(red: 0.23, green: 0.27, blue: 0.18).opacity(0.24)]
        case .sunset:
            return [Color(red: 0.97, green: 0.55, blue: 0.26).opacity(0.32),
                    Color(red: 0.54, green: 0.21, blue: 0.44).opacity(0.22)]
        }
    }

    /// Та же дверь и то же правило, что у фона профиля: «Плюс» кончился —
    /// карточка обычная, выбор в базе цел.
    func effective(isPlus: Bool) -> VehicleCardStyle {
        (self.isPlus && !isPlus) ? .none : self
    }

    static func effective(id raw: String?, isPlus: Bool) -> VehicleCardStyle {
        from(raw).effective(isPlus: isPlus)
    }

    /// Незнакомая строка — обычная карточка, а не падение чужого гаража.
    static func from(_ raw: String?) -> VehicleCardStyle {
        guard let raw, !raw.isEmpty else { return .none }
        return VehicleCardStyle(rawValue: raw) ?? .none
    }
}

/// Заливка карточки. Отдельный тип, чтобы место показа писало одну строку и
/// не собирало градиент у себя — их три (гараж, паспорт, чужой гараж).
struct VehicleCardStyleWash: View {
    let style: VehicleCardStyle
    var cornerRadius: CGFloat = 16

    var body: some View {
        let palette = style.colors
        if palette.isEmpty {
            Color.clear
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(colors: palette,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .allowsHitTesting(false)
        }
    }
}
