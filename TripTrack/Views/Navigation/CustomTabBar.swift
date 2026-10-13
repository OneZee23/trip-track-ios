import SwiftUI

/// Плавающий таб-бар — Лента / Атлас / Запись / Места / Я.
///
/// Геометрия и палитра — из макетов 0.8.1 («Атлас», A1): бумажная капсула в
/// 68 pt, приподнятый на 12 pt диск записи, терракотовый акцент. До 0.8.1
/// этот вид был ТОЛЬКО на «Атласе», а остальные четыре вкладки несли стеклянную
/// пилюлю 0.6.0 в 74 pt — два разных бара в одном приложении, и владелец на
/// устройстве 26 сентября увидел именно это («у нас в атласе вот так, а в
/// остальных местах по-другому»). Бар теперь ОДИН на все вкладки; подпись при
/// этом мельче макетной (10 pt против 11) — решение владельца там же.
///
/// Подпись у диска записи не рисуется вовсе: запись — действие, а не вкладка,
/// и в макете она подписана только иконкой.
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    /// Точка у «Я», пока есть неоткрытые черновики (0.8.2).
    @ObservedObject private var draftsBadge = DraftsBadge.shared

    // MARK: - Геометрия

    /// Капсула без приподнятого диска.
    static let pillHeight: CGFloat = 68
    /// Боковое поле капсулы от края экрана.
    static let sideMargin: CGFloat = 16
    /// Зазор от ФИЗИЧЕСКОГО низа окна. От индикатора «домой» не зависит:
    /// макет ставит бар в 22 pt на любом телефоне, и приподнятый центр уже
    /// заложен в `clearance` ниже.
    static let bottomGap: CGFloat = 22
    /// Насколько диск записи выступает над капсулой.
    static let recordRise: CGFloat = 12

    /// Сколько места снизу оставить контенту экрана, над которым висит бар:
    /// зазор + капсула + подъём диска + 8 pt воздуха. Одно место, откуда это
    /// число читают все вкладки — до 0.6.8 оно было литералом 96 в каждом
    /// экране, и подъём нельзя было поменять, не спрятав под бар последнюю
    /// строку ленты. Держит `CustomTabBarLiftTests`.
    static let clearance: CGFloat = bottomGap + pillHeight + recordRise + 8

    /// Тот же клиренс для скролла, который УВАЖАЕТ безопасную зону снизу —
    /// экраны внутри `NavigationStack` (профиль, гараж, паспорт, лента):
    /// их содержимое кончается на границе зоны, а капсула стоит от
    /// физического низа, и без вычета под последней строкой остаётся лишнее.
    static func clearanceAboveSafeArea(bottomInset: CGFloat) -> CGFloat {
        max(0, clearance - bottomInset)
    }
    /// Читает ПОСЛЕДНЮЮ завершённую разметку окна, а не UIKit во время `body`:
    /// живой `UIWindow` из тела SwiftUI зацикливал обновление на переходах
    /// (0.8.1). Observation перерисовывает читателей, когда приедет первый
    /// замер.
    static var clearanceAboveSafeArea: CGFloat {
        clearanceAboveSafeArea(bottomInset: WindowLayoutMetrics.shared.safeAreaInsets?.bottom ?? 0)
    }

    // MARK: - Бар

    var body: some View {
        HStack(spacing: 0) {
            tab(.home, label: AppStrings.feed(lang.language))
            tab(.maps, label: AppStrings.tabMap(lang.language))
            record
            tab(.places, label: AppStrings.tabPlaces(lang.language))
            tab(.profile, label: AppStrings.tabMe(lang.language))
        }
        .padding(.horizontal, 6)
        .frame(height: Self.pillHeight)
        .background {
            Capsule()
                .fill(AtlasTheme.navSurface.opacity(0.94))
                .overlay {
                    Capsule()
                        .strokeBorder(scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.16), radius: 14, y: 8)
        }
        .padding(.horizontal, Self.sideMargin)
        .padding(.bottom, Self.bottomGap)
    }

    private func tab(_ tab: AppTab, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            // Повторный тап по уже открытой ленте увозит её наверх — это
            // поведение старого бара, и терять его при сведении нельзя.
            if isActive, tab == .home {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            }
            withAnimation(.snappy(duration: 0.22)) {
                selectedTab = tab
            }
            Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                glyph(tab)
                    .overlay(alignment: .topTrailing) {
                        if tab == .profile, draftsBadge.hasUnseen { unseenDot }
                    }
                Text(label)
                    .font(.inter(10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? AtlasTheme.accent : AtlasTheme.navInactive)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        // Точка у «Я» дублируется голосом (спека черновиков §9): то, что
        // видно глазу, обязано быть сказано и вслух.
        .accessibilityValue(tab == .profile && draftsBadge.hasUnseen
                            ? AppStrings.draftsTabHint(lang.language) : "")
        .accessibilityIdentifier("tab_\(tab.rawValue)")
    }

    /// Точка 8 pt с обводкой 2 цветом капсулы — чтобы она читалась и когда
    /// ложится на саму линию иконки. Сдвинута наружу на её половину: у
    /// контурного глифа угол пустой, и точка внутри рамки выглядела бы
    /// частью рисунка.
    private var unseenDot: some View {
        Circle()
            .fill(AtlasTheme.accent)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(AtlasTheme.navSurface, lineWidth: 2))
            .frame(width: 12, height: 12)
            .offset(x: 4, y: -2)
            .accessibilityHidden(true)
    }

    /// Диск 60 pt в кольце подложки 68 pt; `-12` поднимает его центр ровно на
    /// `recordRise`, который уже заложен в `clearance`.
    private var record: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                selectedTab = .record
            }
            Haptics.tap()
        } label: {
            Circle()
                .fill(AtlasTheme.navSurface)
                .frame(width: 68, height: 68)
                .overlay {
                    Circle()
                        .fill(AtlasTheme.accent)
                        .frame(width: 60, height: 60)
                        .overlay {
                            glyph(.record)
                                .scaleEffect(28.0 / 24.0)
                                .foregroundStyle(.white)
                        }
                }
                .shadow(color: AtlasTheme.accent.opacity(0.35), radius: 8, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(y: -Self.recordRise)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(AppStrings.recordTripCta(lang.language))
        .accessibilityIdentifier("tab_record")
    }

    /// Точная геометрия 24×24 из SVG макета. Контурные пути, а не SF Symbols:
    /// у тех другая оптическая плотность и залитая карта.
    private func glyph(_ tab: AppTab) -> some View {
        Path { path in
            switch tab {
            case .home:
                path.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16),
                                    cornerSize: CGSize(width: 3.5, height: 3.5))
                path.move(to: CGPoint(x: 4, y: 12))
                path.addLine(to: CGPoint(x: 20, y: 12))
            case .maps:
                path.move(to: CGPoint(x: 3, y: 6.5))
                for point in [CGPoint(x: 9, y: 3.5), CGPoint(x: 15, y: 6.5),
                              CGPoint(x: 21, y: 3.5), CGPoint(x: 21, y: 17.5),
                              CGPoint(x: 15, y: 20.5), CGPoint(x: 9, y: 17.5),
                              CGPoint(x: 3, y: 20.5)] {
                    path.addLine(to: point)
                }
                path.closeSubpath()
                path.move(to: CGPoint(x: 9, y: 3.5))
                path.addLine(to: CGPoint(x: 9, y: 17.5))
                path.move(to: CGPoint(x: 15, y: 6.5))
                path.addLine(to: CGPoint(x: 15, y: 20.5))
            case .record:
                path.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
                path.addEllipse(in: CGRect(x: 9.8, y: 9.8, width: 4.4, height: 4.4))
                path.move(to: CGPoint(x: 3.8, y: 10.5))
                path.addCurve(to: CGPoint(x: 12, y: 9),
                              control1: CGPoint(x: 6.3, y: 9.5), control2: CGPoint(x: 9, y: 9))
                path.addCurve(to: CGPoint(x: 20.2, y: 10.5),
                              control1: CGPoint(x: 15, y: 9), control2: CGPoint(x: 17.7, y: 9.5))
                path.move(to: CGPoint(x: 12, y: 14.2))
                path.addLine(to: CGPoint(x: 12, y: 20.5))
            case .places:
                path.addEllipse(in: CGRect(x: 8.5, y: 4, width: 7, height: 7))
                path.move(to: CGPoint(x: 12, y: 11))
                path.addLine(to: CGPoint(x: 12, y: 20))
                path.move(to: CGPoint(x: 8, y: 20.5))
                path.addLine(to: CGPoint(x: 16, y: 20.5))
            case .profile:
                path.addEllipse(in: CGRect(x: 8.2, y: 4.2, width: 7.6, height: 7.6))
                path.move(to: CGPoint(x: 4.5, y: 20.5))
                path.addCurve(to: CGPoint(x: 12, y: 14.9),
                              control1: CGPoint(x: 5.9, y: 16.8), control2: CGPoint(x: 8.7, y: 14.9))
                path.addCurve(to: CGPoint(x: 19.5, y: 20.5),
                              control1: CGPoint(x: 15.3, y: 14.9), control2: CGPoint(x: 18.1, y: 16.8))
            }
        }
        .stroke(style: StrokeStyle(lineWidth: tab == .record ? 2 : 1.8, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 24)
    }
}
