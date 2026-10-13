import SwiftUI

/// Превью функции PRO на данных человека — ОДНО место отрисовки на два экрана.
///
/// Его просят страницы демонстрации (180 pt) и контекстный лист (160 pt), и
/// второй копии быть не должно: два способа нарисовать одно и то же расходятся
/// молча — так разошлись круги старого `FogPolygonBuilder` с коридорами карты.
/// Высота приходит параметром, потому что это единственное, чем два места
/// различаются.
struct ProDemoPreviewView: View {
    let preview: ProDemoPreview
    let data: ProDemoData

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var unit

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        content(c, l)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func content(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        switch preview {
        case .profileStrip:      profileStrip(l)
        case .avatarRing:        avatarRing()
        case .vehicleCard:       vehicleCard(data.vehicleTitle ?? "")
        case .vehicleSilhouette: vehicleSilhouette(l)
        case .route:             routeArt(data.route, labelled: false, c, l)
        case .exampleRoute:      routeArt(ProDemoData.exampleRoute, labelled: true, c, l)
        case .manualPins:        manualPins(c)
        }
    }

    // MARK: - Профиль

    private func profileStrip(_ l: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
            Text(data.avatarEmoji)
                .font(.inter(28))
                .frame(width: 56, height: 56)
                .background(Circle().fill(.white.opacity(0.18)))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                .avatarFrame(ProPaywallHero.frame, lineWidth: 3)

            HStack(spacing: 8) {
                Text(data.name)
                    .font(.inter(20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ProBadge()
            }

            Text(statsLine(l))
                .font(AppType.meta)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProPaywallHero.background.view())
    }

    /// «77 поездок · 360 миль». Расстояние — только через `Measure`, с явной
    /// единицей: правило 0.6.7 распространяется и на превью.
    private func statsLine(_ l: LanguageManager.Language) -> String {
        let trips = AppStrings.nounTrips(l, data.trips)
        let distance = Measure.distance(metres: data.distanceMetres, unit: unit, lang: l)
        return "\(trips) · \(distance)"
    }

    private func avatarRing() -> some View {
        Text(data.avatarEmoji)
            .font(.inter(40))
            .frame(width: 80, height: 80)
            .background(Circle().fill(.white.opacity(0.18)))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            .avatarFrame(ProPaywallHero.frame, lineWidth: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ProPaywallHero.background.view())
    }

    // MARK: - Машина

    private func vehicleCard(_ title: String) -> some View {
        ZStack {
            VehicleCardStyleWash(style: ProDemoData.cardStyle, cornerRadius: 0)
            VStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.92))
                Text(title)
                    .font(.inter(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Гаража нет — силуэт С ПОДПИСЬЮ (состояние 3). Подпись обязательна: без
    /// неё пустая карточка читается поломкой, а не примером.
    private func vehicleSilhouette(_ l: LanguageManager.Language) -> some View {
        ZStack {
            VehicleCardStyleWash(style: ProDemoData.cardStyle, cornerRadius: 0)
            VStack(spacing: 6) {
                Image(systemName: "car.side")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.55))
                Text(AppStrings.proDemoCarEmptyTitle(l))
                    .font(.inter(17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(AppStrings.proDemoCarEmptySub(l))
                    .font(AppType.meta)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Маршрут

    private func routeArt(
        _ points: [CGPoint], labelled: Bool,
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ProRouteArt(points: points, color: ProDemoData.lineColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(c.cardAlt)
            if labelled {
                Text(AppStrings.proDemoExample(l))
                    .font(.inter(11, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(c.card.opacity(0.9)))
                    .padding(10)
            }
        }
    }

    private func manualPins(_ c: AppTheme.Colors) -> some View {
        ProRouteArt(points: ProDemoData.manualRoute,
                    color: AppTheme.accent,
                    dashed: true,
                    endpoints: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(c.cardAlt)
    }
}
