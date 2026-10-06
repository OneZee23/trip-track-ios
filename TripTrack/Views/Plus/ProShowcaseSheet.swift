import SwiftUI

/// Витрина оформления — состояния 21…27 матрицы 0.8.4.
///
/// ОДИН лист на все четыре косметики, потому что макет у них один: заголовок,
/// закреплённое превью, две группы плиток со своими числами, полоса стекла с
/// единственной кнопкой. Четыре копии этого кода разошлись бы — и разошлись
/// бы именно в том, что важно: в замке у платной плитки.
///
/// **Витрина не выбрасывает на пейвол** (принцип §1.4). Премиальный вариант
/// сначала ПРИМЕРЯЕТСЯ в превью — человек видит себя с ним, — и только кнопка
/// внизу предлагает купить. До 0.8.4 тап по замку уводил на пейвол сразу, то
/// есть отвечал предложением на «покажи».
struct ProShowcaseSheet: View {
    let kind: ProShowcaseKind
    /// Что выбрано в базе сейчас. Внутри листа примерка живёт в своём
    /// состоянии: закрыть лист крестиком, ничего не купив, не должно менять
    /// сохранённый выбор.
    let current: String
    var vehicleID: UUID? = nil
    /// Человек выбрал вариант, доступный ему. Платный без подписки сюда НЕ
    /// приходит — он только примеряется.
    let onPick: (String) -> Void
    /// «Оформить PRO» / «Продлить» — единственная дорога к покупке отсюда.
    let onOpenPro: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var plus = PlusAccess.shared
    @ObservedObject private var plusStore = PlusStore.shared
    @ObservedObject private var settings = SettingsManager.shared

    /// Что примеряется прямо сейчас. Отдельно от `current`: примерка платного
    /// меняет превью, но не базу.
    @State private var tried: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let state = showcaseState
        let shown = shownID

        VStack(spacing: 0) {
            header(c, l)
            preview(shown, c)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if ProShowcase.showsExpiredCard(state), let retainedName {
                        expiredCard(c, l, retainedName: retainedName)
                    }
                    if kind == .routeLine {
                        // Макет рисует бесплатный вариант линии СТРОКОЙ, а не
                        // плиткой (спека, состояние 27), и правильно: у
                        // «По скорости» нет имени собственного — у него
                        // описание ПОВЕДЕНИЯ, и в кружок 44 оно не влезает.
                        // Плиткой оно и выходило без подписи вовсе:
                        // `RouteLineStyle.displayName` для `.speed` пуст по
                        // построению (находка финального ревью).
                        speedRow(shown, c, l)
                    } else {
                        group(AppStrings.showcaseFree(l), kind.freeCount,
                              ProShowcase.groups(for: kind).free, shown, state, c)
                    }
                    if ProShowcase.showsPremiumGroup(kind, state) {
                        group(AppStrings.showcasePro(l), kind.premiumCount,
                              ProShowcase.groups(for: kind).premium, shown, state, c)
                    }
                    if let note = footnote(l) {
                        Text(note)
                            .font(AppType.caption)
                            .foregroundStyle(c.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("pro_showcase_footnote")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            footer(state, c, l)
        }
        .background(c.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_showcase_\(kind.feature.proIcon)")
    }

    // MARK: - Состояние

    private var shownID: String {
        ProShowcase.previewID(
            for: kind, current: current, tried: tried,
            isPlus: plus.isPlus, storefrontHidesPlus: plus.storefrontHidesPlus)
    }

    private var showcaseState: ProShowcase.State {
        ProShowcase.State(
            isPlus: plus.isPlus,
            storefrontHidesPlus: plus.storefrontHidesPlus,
            // Примерка — это выбранный ПЛАТНЫЙ вариант без подписки.
            tryingOnPremium: isPremium(shownID) && !plus.isPlus,
            proHasEnded: plusStore.state == .expired,
            freeWeekAvailable: plusStore.introEligible)
    }

    private func isPremium(_ id: String) -> Bool {
        ProShowcase.tiles(for: kind).first { $0.id == id }?.isPremium ?? false
    }

    private var retainedName: String? {
        guard let id = settings.retainedCosmeticID(kind, current: current,
                                                   vehicleID: vehicleID) else { return nil }
        return ProShowcase.tiles(for: kind).first { $0.id == id && $0.isPremium }?.name
    }

    // MARK: - Шапка

    private func header(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        ZStack {
            Text(kind.title(l))
                .font(.inter(17, weight: .semibold))
                .foregroundStyle(c.text)
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(c.cardAlt))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pro_showcase_close")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    // MARK: - Превью

    /// Превью ЗАКРЕПЛЕНО и показывает примеряемый вариант: человек покупает
    /// не фон, а себя с этим фоном.
    @ViewBuilder
    private func preview(_ shown: String, _ c: AppTheme.Colors) -> some View {
        switch kind {
        case .profileBackground:
            ProShowcasePreview.profile(
                background: ProfileBackground.from(shown),
                frame: AvatarFrame.effective(id: settings.avatarFrame, isPlus: plus.isPlus))
        case .avatarFrame:
            ProShowcasePreview.profile(
                background: ProfileBackground.effective(
                    id: settings.profileBackground, isPlus: plus.isPlus),
                frame: AvatarFrame.from(shown))
        case .vehicleCard:
            ProShowcasePreview.vehicle(style: VehicleCardStyle.from(shown))
        case .routeLine:
            ProShowcasePreview.route(style: RouteLineStyle.from(shown), c)
        }
    }

    // MARK: - Группы

    private func group(
        _ title: String,
        _ count: Int,
        _ tiles: [ProShowcase.Tile],
        _ shown: String,
        _ state: ProShowcase.State,
        _ c: AppTheme.Colors
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(AppType.section)
                    .tracking(AppType.sectionTracking)
                    .foregroundStyle(c.text)
                Text("\(count)")
                    .font(AppType.meta)
                    .foregroundStyle(c.textTertiary)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(tiles) { tile in
                    tileButton(tile, isSelected: tile.id == shown, state, c)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «По скорости» — строкой с описанием поведения (состояние 27).
    private func speedRow(
        _ shown: String,
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language
    ) -> some View {
        let isSelected = shown == RouteLineStyle.speed.rawValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(AppStrings.showcaseFree(l))
                    .font(AppType.section)
                    .tracking(AppType.sectionTracking)
                    .foregroundStyle(c.text)
            }
            Button {
                Haptics.selection()
                tried = RouteLineStyle.speed.rawValue
                onPick(RouteLineStyle.speed.rawValue)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(
                            colors: [AppTheme.green, AppTheme.yellow, AppTheme.red],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppStrings.showcaseLineSpeed(l))
                            .font(AppType.itemTitle)
                            .foregroundStyle(isSelected ? AppTheme.accent : c.text)
                        Text(AppStrings.showcaseLineSpeedSub(l))
                            .font(AppType.meta)
                            .foregroundStyle(c.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .surfaceCard(cornerRadius: 16)
            .accessibilityIdentifier("pro_tile_speed")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tileButton(
        _ tile: ProShowcase.Tile,
        isSelected: Bool,
        _ state: ProShowcase.State,
        _ c: AppTheme.Colors
    ) -> some View {
        let locked = ProShowcase.isLocked(isPremium: tile.isPremium, state: state)
        return Button {
            Haptics.selection()
            // Платный без подписки ПРИМЕРЯЕТСЯ, а не выбирается: в базу он
            // не уходит, и кнопка внизу становится предложением.
            tried = tile.id
            if !locked { onPick(tile.id) }
        } label: {
            ProShowcaseTileView(kind: kind, tile: tile,
                                isSelected: isSelected, isLocked: locked)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("pro_tile_\(tile.id.isEmpty ? "none" : tile.id)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Сноска под сеткой — «кому это видно».
    ///
    /// Перенесена из домашних пикеров, которые витрина заменила: у цвета линии
    /// и у фона карточки машины они БЫЛИ, и в них лежал ответ, которого больше
    /// нигде нет («цвет виден только на ваших картах», «фон видно в гараже и в
    /// публичном профиле»). Витрина макета сноски не рисует, но потерять этот
    /// ответ значило бы оставить подписчика, который до страниц демонстрации
    /// не доходит, без него вовсе: демонстрацию видит тот, кто ещё НЕ купил.
    ///
    /// У фона профиля и рамки аватара сноски нет: они видны в ленте и в
    /// профиле, то есть там же, где сам человек, и объяснять это нечем.
    private func footnote(_ l: LanguageManager.Language) -> String? {
        switch kind {
        case .routeLine:   return AppStrings.routeLinePickerFootnote(l)
        case .vehicleCard: return AppStrings.vehicleCardStylePickerFootnote(l)
        case .profileBackground, .avatarFrame: return nil
        }
    }

    // MARK: - Карточка «PRO закончился»

    /// Первым делом — что выбор НЕ ПОТЕРЯН: человек, увидевший свой обычный
    /// фон вместо купленного, боится, что настройку стёрли.
    private func expiredCard(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language, retainedName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.showcaseExpiredTitle(l, date: expiredDate(l)))
                .font(AppType.itemValue)
                .foregroundStyle(c.text)
            Text(AppStrings.cosmeticRetainedChoice(l, kind: kind, name: retainedName))
                .font(AppType.body)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.accentBg))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pro_showcase_expired")
    }

    private func expiredDate(_ l: LanguageManager.Language) -> String {
        guard let until = plusStore.displayExpiry,
              let formatter = Self.formatters[l] else { return "" }
        return formatter.string(from: until)
    }

    private static let formatters = LocalizedDateFormatter.templates("dMMM")

    // MARK: - Подвал

    /// Полоса стекла с ОДНОЙ кнопкой: «Готово», «Попробовать неделю
    /// бесплатно», «Оформить PRO» или «Продлить» — решает `ProShowcase`.
    private func footer(
        _ state: ProShowcase.State,
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language
    ) -> some View {
        let action = ProShowcase.action(state)
        return Button {
            Haptics.action()
            if action.opensPro { onOpenPro() } else { dismiss() }
        } label: {
            Text(action.title(l))
                .font(AppType.button)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.accent))
        }
        .buttonStyle(PressableCardStyle())
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(c.bg.opacity(0.82))
            }
            // Полоса достаёт до физического края, содержимое остаётся в
            // безопасной зоне — та же дисциплина, что у подвала витрины PRO.
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(c.border).frame(height: 1)
        }
        .accessibilityIdentifier("pro_showcase_action")
    }
}
