import SwiftUI

/// Карта публичных поездок другого человека (0.6.3).
///
/// Это НЕ вторая карта. Рендер тот же самый — `MyMapRepresentable`,
/// `MyMapOverlays`, `MapExploration`, — меняется ровно один вход: поездки
/// приезжают из `RemoteTripSource`, а не из CoreData. Карту предстоит
/// переделывать до 1.0, и правка обязана менять оба места сразу; форк рендера
/// не завёлся бы обратно.
///
/// Своя карта живёт в `MyMapViewModel.shared` — синглтоне, который переживает
/// переключение табов. Здесь намеренно СВОЙ экземпляр: чужой аккаунт, заехавший
/// в общий, стёр бы состояние карты владельца.
struct PublicMapView: View {
    let accountId: UUID
    let ownerName: String?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm: MyMapViewModel

    init(accountId: UUID, ownerName: String?) {
        self.accountId = accountId
        self.ownerName = ownerName
        _vm = StateObject(wrappedValue: MyMapViewModel(
            source: RemoteTripSource(accountId: accountId)))
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ZStack {
            MyMapRepresentable(
                exploration: vm.exploration,
                fog: vm.fogOverlay,
                veil: MyMapView.showsVeil ? vm.fogVeil : nil,
                selectedRoute: vm.selectedRoute,
                selection: vm.selection,
                highlightedRegionId: vm.highlightedRegionId,
                language: l,
                onZoomLevelChange: { _ in },
                onSelectTrip: { _ in },
                onSelectRoad: { _ in },
                // Чужие объекты не открываются: у смотрящего нет прав ни на
                // деталку поездки, ни на разбор региона.
                onTapMap: { _ in },
                cameraCommand: $vm.cameraCommand
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header(c, l)
                Spacer(minLength: 0)
                summary(c, l)
            }

            if vm.isLoading { CarLoadingView() }
        }
        .navigationBarHidden(true)
        .task { await vm.loadRemote() }
    }

    // MARK: - Шапка

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            // Домовая кнопка, а не своя: она предпочитает `\.previewPop`
            // обычному `\.dismiss`. Внутри `PreviewNavigator` вокруг экрана
            // нет NavigationStack, и `dismiss()` там снёс бы весь
            // fullScreenCover вместо возврата в профиль.
            NavBackButton()
                .accessibilityLabel(AppStrings.back(l))
                .accessibilityIdentifier("public_map_back")

            Spacer(minLength: 0)
            titlePill(c, l)
            Spacer(minLength: 0)

            // Балансир под кнопку, чтобы пилюля стояла по центру.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func titlePill(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 1) {
            Text(ownerName ?? AppStrings.profileMapEntryTitle(l))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(c.text)
            // Рамка обязательна: счётчики профиля считаются по ВСЕМ поездкам,
            // а карта рисует только публичные. Без подписи расхождение между
            // «47 поездок» в профиле и дюжиной маршрутов здесь читается как баг.
            Text(AppStrings.publicRoutesCaption(l))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(c.glass, in: Capsule())
    }

    // MARK: - Нижний лист

    private func summary(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(c.border)
                .frame(width: 36, height: 4)

            if vm.isLoading {
                // Иначе сводка утверждает «0 маршрутов · 0 км · 0 регионов» про
                // другого человека всё время загрузки — то есть врёт точными
                // числами. Статистика этот случай уже закрывает.
                // Ничего, кроме ручки листа: `CarLoadingView` уже висит
                // оверлеем поверх карты и говорит о загрузке за нас.
                Color.clear.frame(height: 24)
            } else if vm.remoteFailed && vm.exploration.trips.isEmpty {
                // Отказ загрузки — НЕ «человек ничего не опубликовал». Второе
                //утверждение о другом человеке, которого мы не проверяли.
                Text(AppStrings.publicDataLoadFailed(l))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(c.text)
                Button { Task { await vm.loadRemote() } } label: {
                    Text(AppStrings.retry(l))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            } else if vm.isEmpty {
                // Ноль публичных поездок — это пустое состояние, а не отказ
                // загрузки: человек просто ничего не опубликовал.
                Text(AppStrings.publicMapEmptyTitle(l))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(c.text)
                Text(AppStrings.publicMapEmptyBody(l))
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(c.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Вне блока с именем: неизвестное имя не повод молчать о том,
                // что числа под ним занижены.
                if vm.remoteFailed {
                    Text(AppStrings.publicDataPartial(l))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 0) {
                    cell(String(vm.exploration.trips.count),
                         AppStrings.publicRoutesCaption(l), c)
                    rule(c)
                    cell(GarageFormat.odometer(vm.exploration.totalKm, lng: l),
                         AppStrings.km(l), c)
                    rule(c)
                    cell(String(vm.exploration.regions.count),
                         AppStrings.statsRegions(l), c)
                }
                // Только когда имя известно: с пустой подстановкой фраза
                // разваливается в «Здесь только те поездки, которые  сделал
                // публичными». Подпись под заголовком всё равно сказала главное.
                if let name = ownerName?.trimmingCharacters(in: .whitespaces),
                   !name.isEmpty {
                    Text(AppStrings.publicRoutesExplainer(l, name: name))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(
            c.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 28, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 28)
        )
    }

    private func cell(_ value: String, _ label: String, _ c: AppTheme.Colors) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(c.text)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rule(_ c: AppTheme.Colors) -> some View {
        Rectangle().fill(c.border).frame(width: 1, height: 26)
    }
}
