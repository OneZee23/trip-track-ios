import SwiftUI

/// Гараж другого человека — экран 16 канона 0.6.4.
///
/// Показываются только машины, которые владелец открыл. Счётчика «показаны 2
/// из 5» здесь нет и быть не может: он выдал бы, сколько человек прячет.
///
/// По той же причине пустой гараж и полностью скрытый гараж выглядят
/// ОДИНАКОВО. Плашка «гараж закрыт» утверждала бы, что машины есть, — то есть
/// отличала бы человека, который прячет, от человека, у которого нечего
/// прятать, а это ровно та утечка, которой не должно быть.
struct PublicGarageView: View {
    let accountId: UUID
    let ownerName: String?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var vehicles: [PublicVehicle] = []
    @State private var state: LoadState = .loading
    @State private var openVehicle: PublicVehicle?

    private enum LoadState { case loading, loaded, failed }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            nav(c: c, l: l)
            content(c: c, l: l)
        }
        .background(c.bg.ignoresSafeArea())
        // У экрана СВОЯ шапка с шевроном, поэтому системный навбар прячем —
        // иначе на экране две кнопки «назад», и непонятно, чем они разные.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: accountId) { await load() }
        .navigationDestination(item: $openVehicle) { v in
            PublicVehicleView(accountId: accountId, vehicleId: v.id,
                              ownerName: ownerName, preloaded: v)
                .environmentObject(lang)
        }
    }

    @ViewBuilder
    private func content(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        switch state {
        case .loading:
            Spacer()
            CarLoadingView()
            Spacer()

        case .failed:
            // Отказ сети — НЕ «гараж пуст». Разные причины требуют разных
            // слов и разных кнопок: пустоту не перезагружают.
            VStack(spacing: 12) {
                Spacer()
                Text(AppStrings.garageLoadFailed(l))
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                Button {
                    Haptics.tap()
                    Task { await load() }
                } label: {
                    Text(AppStrings.retry(l))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(AppTheme.accent.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(maxWidth: .infinity)

        case .loaded where vehicles.isEmpty:
            VStack(spacing: 8) {
                Spacer()
                Text(AppStrings.publicGarageEmpty(l))
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .frame(maxWidth: .infinity)

        case .loaded:
            ScrollView {
                VStack(spacing: 10) {
                    // Проданные уходят вниз, но остаются на виду: машина, на
                    // которой человек отъездил десять лет, — часть его истории,
                    // и прятать её от других незачем. Порядок говорит, что она
                    // уже не в строю, метка — почему.
                    ForEach(vehicles.sorted { !$0.isSold && $1.isSold }) { v in
                        row(v, c: c, l: l)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ v: PublicVehicle, c: AppTheme.Colors,
                     l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            openVehicle = v
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Та же форма, что в собственном гараже: одна высота полосы,
                // фотография или силуэт. Чужой гараж не должен выглядеть
                // устройством иначе, чем свой.
                VehicleFace(
                    photo: .remote(v.mainPhoto),
                    assetName: VehicleAvatar.assetName(
                        style: v.avatarStyle, avatar: v.avatarEmoji),
                    fallbackEmoji: v.avatarEmoji,
                    style: .banner,
                    dimmed: v.isSold
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(v.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        if v.isSold {
                            Text(AppStrings.vehicleSoldBadge(l))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(c.textTertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(c.cardAlt, in: Capsule())
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                    if let line = v.modelLine(l) {
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 10) {
                        VehicleXPBar(
                            progress: VehicleLevelSystem.progressToNext(
                                km: v.odometerKm, level: v.level),
                            tint: VehicleLevelSystem.color(for: v.level)
                        )
                        VehicleLevelPill(level: v.level, size: 9)
                    }
                    .padding(.top, 2)
                    Text(GarageFormat.odometer(v.odometerKm, lng: l) + " " + AppStrings.km(l))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        // Обычный отклик, а не «держи и что-то будет»: долгого меню на чужой
        // машине нет, и обещать его затяжным сжатием — врать пальцу.
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
    }

    /// Собрано функцией, а не интерполяцией: несколько подстановок в одном
    /// `Text` стоят минут тайпчекинга (см. историю сборки гаража).
    private func subtitle(_ v: PublicVehicle, _ l: LanguageManager.Language) -> String {
        var parts: [String] = []
        if let line = v.modelLine(l) { parts.append(line) }
        parts.append(GarageFormat.odometer(v.odometerKm, lng: l) + " " + AppStrings.km(l))
        return parts.joined(separator: " · ")
    }

    private func nav(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(AppStrings.garage(l))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(c.text)
                if let ownerName {
                    Text(ownerName)
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.text)
                        // 44×44 — минимум, ниже которого палец промахивается,
                        // а VoiceOver читает «кнопка» без имени: у картинки
                        // подписи нет, и системный ярлык её не заменяет.
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppStrings.back(l))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private func load() async {
        state = .loading
        do {
            let res: PublicGarageResponse = try await APIClient.shared.get(
                APIEndpoint.userGarage(accountId.uuidString),
                requiresAuth: AuthService.shared.isSignedIn)
            vehicles = res.vehicles
            state = .loaded
        } catch {
            // Пустой список при ошибке был бы ложью о другом человеке: экран
            // сказал бы «у него нет машин», хотя он их просто не получил.
            vehicles = []
            state = .failed
        }
    }
}
