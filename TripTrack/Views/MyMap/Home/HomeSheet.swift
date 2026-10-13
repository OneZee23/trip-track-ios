import CoreLocation
import SwiftUI

/// Настройка дома и приватной зоны (0.8.2, доска макета A7).
///
/// Всё про дом живёт здесь, одним экраном: поставить точку, показывать ли
/// метку, радиус, обрезать ли публичные треки, убрать дом. В лист «Вид карты»
/// вынесена ОДНА строка со сводкой — тумблер там означал бы переключатель у
/// того, чего, может быть, ещё нет.
struct HomeSheet: View {
    @ObservedObject private var manager = HomeManager.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @State private var showRemove = false

    var body: some View {
        let l = lang.language
        VStack(spacing: 0) {
            AtlasControlsHeader(title: AppStrings.homeSheetTitle(l))
            ScrollView {
                VStack(spacing: 16) {
                    mapCard
                    if manager.settings.isSet {
                        visibilityCard
                        radiusCard
                        zoneCard
                        removeButton
                    }
                }
                .padding(16)
            }
        }
        .background(AtlasTheme.background)
        .presentationBackground(AtlasTheme.background)
        .presentationCornerRadius(AtlasTheme.sheetRadius)
        .presentationDragIndicator(.hidden)
        // Диалог висит на КОРНЕ экрана, а не внутри прокрутки: накладка
        // размером с секцию уезжала бы вместе со скроллом (CLAUDE.md).
        .appConfirm(
            isPresented: $showRemove,
            title: AppStrings.homeRemoveTitle(l),
            // Переотправка бывает, только если зона включена (`activeZone`):
            // по умолчанию она выключена, и без неё обещать «отправим заново»
            // значило бы пугать работой, которой не будет.
            message: manager.settings.activeZone != nil
                ? AppStrings.homeRemoveBody(l)
                : AppStrings.homeRemoveBodyNoZone(l),
            actions: [
                AppDialogAction(AppStrings.homeRemove(l), kind: .destructive) {
                    manager.remove()
                }
            ]
        )
        // Имя листа — на МАРКЕРЕ, а не на контейнере.
        //
        // `accessibilityIdentifier` на контейнере SwiftUI раздаёт ВСЕМ детям
        // внутри: кнопка × получала «home_sheet» вместо своего
        // «atlas_controls_close», и закрыть лист из теста было нечем — а
        // соседний тест на этом молча проходил, тыкая не туда. То же
        // правило, что у заголовка секции подсказок (CLAUDE.md, 0.8.0).
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("home_sheet")
        }
    }

    // MARK: Карта

    private var mapCard: some View {
        HomePickerMapView(
            home: manager.settings.coordinate,
            fallback: MyMapViewModel.shared.exploration.trips.first?.coordinate,
            radius: Double(manager.settings.radius.rawValue),
            onPlace: { manager.place(at: $0) }
        )
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            // Подсказка стоит, только пока дома нет: она объясняет
            // единственное действие экрана, а объяснять его во второй раз
            // значит занимать карту, на которую человек и смотрит.
            if !manager.settings.isSet {
                Text(AppStrings.homePlaceHint(lang.language))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .accessibilityIdentifier("home_map")
    }

    // MARK: Видимость

    private var visibilityCard: some View {
        let l = lang.language
        return card {
            Toggle(AppStrings.homeShowOnMap(l), isOn: Binding(
                get: { manager.settings.showsOnMap },
                set: { manager.setShowsOnMap($0) }
            ))
            .font(AppType.itemValue)
            .foregroundStyle(AtlasTheme.ink)
            .tint(AtlasTheme.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home_shows_toggle")

            note(AppStrings.homeVisibleOnlyToYou(l))
        }
    }

    // MARK: Радиус

    private var radiusCard: some View {
        let l = lang.language
        return card {
            Text(AppStrings.homeRadiusTitle(l))
                .font(AppType.section)
                .foregroundStyle(AtlasTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(HomeSettings.Radius.allCases, id: \.self) { step in
                    radiusChip(step, l)
                }
            }
        }
    }

    private func radiusChip(_ step: HomeSettings.Radius, _ l: LanguageManager.Language) -> some View {
        let on = manager.settings.radius == step
        return Button {
            Haptics.tap()
            manager.setRadius(step)
        } label: {
            Text(Measure.radius(metres: Double(step.rawValue), unit: distanceUnit, lang: l))
                .font(on ? AppType.chipActive : AppType.chip)
                .foregroundStyle(on ? .white : AtlasTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(on ? AtlasTheme.accent : AtlasTheme.chip,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("home_radius_\(step.rawValue)")
    }

    // MARK: Зона

    private var zoneCard: some View {
        let l = lang.language
        return card {
            Toggle(AppStrings.homeZoneToggle(l), isOn: Binding(
                get: { manager.settings.trimsPublicTracks },
                set: { manager.setTrimsPublicTracks($0) }
            ))
            .font(AppType.itemValue)
            .foregroundStyle(AtlasTheme.ink)
            .tint(AtlasTheme.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home_zone_toggle")

            // Цена нажатия названа ДО нажатия: включение переотправляет все
            // уже опубликованные поездки. Узнать об этом постфактум — значит
            // получить работу, о которой не просил.
            note(AppStrings.homeZoneNote(l))
        }
    }

    private var removeButton: some View {
        Button {
            Haptics.tap()
            showRemove = true
        } label: {
            Text(AppStrings.homeRemove(lang.language))
                .font(AppType.action)
                .foregroundStyle(AppTheme.red)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("home_remove")
    }

    // MARK: Кирпичи

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtlasTheme.card,
                    in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppType.meta)
            .foregroundStyle(AtlasTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
