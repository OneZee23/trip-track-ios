import SwiftUI

/// Строка набора на витрине PRO — одна из пяти функций, 52 pt.
///
/// Плитка 28 со значком, заголовок, серая строка, шеврон. Шеврон стоит потому,
/// что нажатие ОТКРЫВАЕТ демонстрацию этой функции на его собственных данных;
/// правило «если нажатие что-то открывает — это видно» (CLAUDE.md).
struct ProFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.interScaled(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(c.text)
                    Text(subtitle)
                        .font(.interScaled(13, relativeTo: .footnote))
                        .foregroundStyle(c.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("pro_feature_\(icon)")
    }
}

/// Пять функций набора — закрытый список, тот же, что у `PlusFeature`.
///
/// Порядок и разбивка на группы — из макета: сначала то, что видят другие,
/// потом то, что видно только владельцу. Значок, заголовок и подпись живут
/// здесь, а не в экране: их читают и витрина, и контекстные листы задачи 6, и
/// разъехаться этим двум местам нельзя.
extension PlusFeature {
    /// SF Symbol. Системный шрифт здесь обязателен — у Inter нет его глифов
    /// (правило 0.8.1).
    var proIcon: String {
        switch self {
        case .profileBackgrounds: return "photo.artframe"
        case .avatarFrame:        return "circle.circle"
        case .vehicleCardStyle:   return "car.side"
        case .routeLineStyle:     return "point.topleft.down.curvedto.point.bottomright.up"
        case .manualTrip:         return "pencil.line"
        }
    }

    func proTitle(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .profileBackgrounds: return AppStrings.proFeatureBg(lang)
        case .avatarFrame:        return AppStrings.proFeatureFrame(lang)
        case .vehicleCardStyle:   return AppStrings.proFeatureCar(lang)
        case .routeLineStyle:     return AppStrings.proFeatureLine(lang)
        case .manualTrip:         return AppStrings.proFeatureManual(lang)
        }
    }

    func proSubtitle(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .profileBackgrounds: return AppStrings.proFeatureBgSub(lang)
        case .avatarFrame:        return AppStrings.proFeatureFrameSub(lang)
        case .vehicleCardStyle:   return AppStrings.proFeatureCarSub(lang)
        case .routeLineStyle:     return AppStrings.proFeatureLineSub(lang)
        case .manualTrip:         return AppStrings.proFeatureManualSub(lang)
        }
    }

    /// Видно ли это другим людям. От этого зависит группа на витрине, и
    /// вопрос принадлежит самой функции: фон профиля видят в ленте, цвет линии
    /// маршрута — нет.
    var isVisibleToOthers: Bool {
        switch self {
        case .profileBackgrounds, .avatarFrame, .vehicleCardStyle: return true
        case .routeLineStyle, .manualTrip:                         return false
        }
    }
}
