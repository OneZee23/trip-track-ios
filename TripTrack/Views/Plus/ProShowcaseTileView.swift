import SwiftUI

/// Плитка варианта в витрине оформления.
///
/// Размеры из макета: фон и карточка машины 114 × 76 радиусом 12, рамка
/// 114 × 84, цвет линии кружком 44. Обводка выбора — 2 с отступом 2, чтобы
/// она не съедала сам вариант; замок 20 в правом верхнем углу.
struct ProShowcaseTileView: View {
    let kind: ProShowcaseKind
    let tile: ProShowcase.Tile
    let isSelected: Bool
    let isLocked: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 6) {
            ZStack {
                swatch(c)
                if isLocked { lock }
            }
            .frame(height: kind == .avatarFrame ? 84 : 76)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.cardAlt))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .inset(by: -2)
                        .strokeBorder(AppTheme.accent, lineWidth: 2)
                }
            }

            if !tile.name.isEmpty {
                Text(tile.name)
                    .font(.inter(11, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// Замок белым по 92 %, как в макете: на тёмном премиальном фоне серый
    /// замок пропал бы, а акцентный читался бы как «нажми сюда».
    private var lock: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black.opacity(0.55))
            .frame(width: 20, height: 20)
            .background(Circle().fill(.white.opacity(0.92)))
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .topTrailing)
            .padding(6)
    }

    /// Сам вариант. Рисуется теми же видами, что и живые места показа
    /// (`ProfileBackground.view`, `AvatarFrameRing`, `VehicleCardStyleWash`,
    /// `RouteLineStyle.color`): плитка, нарисованная своим способом, обещала
    /// бы не то, что человек получит.
    @ViewBuilder
    private func swatch(_ c: AppTheme.Colors) -> some View {
        switch kind {
        case .profileBackground:
            let background = ProfileBackground.from(tile.id)
            if background == .none { empty(c) } else { background.view() }
        case .avatarFrame:
            Text(verbatim: "Н")
                .font(.inter(17, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(c.card))
                .avatarFrame(AvatarFrame.from(tile.id), lineWidth: 3)
        case .vehicleCard:
            let style = VehicleCardStyle.from(tile.id)
            if style == .none { empty(c) } else {
                VehicleCardStyleWash(style: style, cornerRadius: 12)
            }
        case .routeLine:
            let style = RouteLineStyle.from(tile.id)
            if let colour = style.color {
                Circle().fill(colour).frame(width: 44, height: 44)
            } else {
                // «По скорости» — не цвет, а поведение: градиент, которым
                // маршрут и рисуется.
                Circle()
                    .fill(LinearGradient(
                        colors: [AppTheme.green, AppTheme.yellow, AppTheme.red],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
            }
        }
    }

    /// «Без варианта» — перечёркнутый круг, тот же знак, что в прежнем пикере
    /// фонов: пустая плитка читалась бы незагрузившейся.
    private func empty(_ c: AppTheme.Colors) -> some View {
        Image(systemName: "slash.circle")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(c.textTertiary)
    }
}

/// Закреплённое превью витрины — то, что человек получит.
enum ProShowcasePreview {
    /// Полоса профиля: фон, аватар в рамке, имя, число поездок.
    static func profile(
        background: ProfileBackground, frame: AvatarFrame
    ) -> some View {
        ProShowcaseProfilePreview(background: background, frame: frame)
    }

    static func vehicle(style: VehicleCardStyle) -> some View {
        ProShowcaseVehiclePreview(style: style)
    }

    static func route(style: RouteLineStyle, _ c: AppTheme.Colors) -> some View {
        ProRouteArt(points: ProDemoData.exampleRoute,
                    color: style.color ?? AppTheme.accent)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(c.cardAlt)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProShowcaseProfilePreview: View {
    let background: ProfileBackground
    let frame: AvatarFrame

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 12) {
            Text(settings.avatarEmoji)
                .font(.inter(20))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.18)))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                .avatarFrame(frame, lineWidth: 3)

            Text(ProDemoData.currentName(lang: lang.language))
                .font(.inter(17, weight: .semibold))
                .foregroundStyle(background == .none ? c.text : .white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 120)
        .background {
            if background == .none { c.cardAlt } else { background.view() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProShowcaseVehiclePreview: View {
    let style: VehicleCardStyle

    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let vehicle = settings.vehicles.first
        return ZStack {
            if style == .none { c.cardAlt } else {
                VehicleCardStyleWash(style: style, cornerRadius: 0)
            }
            VStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(style == .none ? c.textSecondary : .white.opacity(0.92))
                Text(vehicle?.name ?? AppStrings.proDemoCarEmptyTitle(.en))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(style == .none ? c.text : .white)
                    .lineLimit(1)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
