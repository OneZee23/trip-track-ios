import SwiftUI

/// «Кого пускать» — экран 13 канона 0.6.4: четыре оси видимости машины.
///
/// Оси РАЗДЕЛЬНЫЕ, и это главное решение экрана. Спрятать номер, не пряча
/// машину; спрятать карту, не пряча машину; спрятать фотографии, не пряча
/// ничего остального. Один общий выключатель «показывать машину» выглядел бы
/// проще, но заставлял бы выбирать между «всё» и «ничего» там, где у человека
/// есть промежуточный ответ.
///
/// Умолчания разные и каждое обосновано:
/// - машина видна (так видно и сегодня, менять задним числом нельзя);
/// - номер СКРЫТ (по номеру в России находят имя и адрес владельца);
/// - карта видна (без неё паспорт наполовину пуст);
/// - фотографии СКРЫТЫ (на снимке во дворе виден и номер, и дом).
struct VehiclePrivacyView: View {
    let vehicleId: UUID

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    @State private var visibleToOthers = true
    @State private var plateVisible = false
    @State private var mapVisible = true
    @State private var photosVisible = false
    @State private var loaded = false

    private var vehicle: Vehicle? {
        settings.vehicles.first { $0.id == vehicleId }
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            nav(c: c, l: l)
            ScrollView {
                VStack(spacing: 12) {
                    axis(AppStrings.showVehicleToggle(l),
                         AppStrings.showVehicleHint(l),
                         isOn: $visibleToOthers, c: c)

                    // Три оставшиеся оси имеют смысл только у ВИДИМОЙ машины:
                    // прятать номер у машины, которой никто не видит, — это
                    // выбор без последствий, и показывать его значит врать
                    // о том, что он на что-то влияет.
                    if visibleToOthers {
                        if vehicle?.hasPlate == true {
                            axis(AppStrings.plateShowToOthers(l),
                                 AppStrings.plateVisibilityHint(l),
                                 isOn: $plateVisible, c: c)
                        }
                        axis(AppStrings.vehicleShowMap(l),
                             AppStrings.vehicleShowMapHint(l),
                             isOn: $mapVisible, c: c)
                        axis(AppStrings.vehicleShowPhotos(l),
                             AppStrings.vehicleShowPhotosHint(l),
                             isOn: $photosVisible, c: c)
                    }

                    Text(AppStrings.vehiclePrivacyFooter(l))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .animation(.easeInOut(duration: 0.2), value: visibleToOthers)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        // У экрана СВОЯ шапка с шевроном, поэтому системный навбар прячем —
        // иначе на экране две кнопки «назад», и непонятно, чем они разные.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: vehicleId) { loadState() }
        // Пишем на КАЖДОЕ изменение, а не по кнопке «Готово»: у экрана из
        // одних тумблеров кнопка сохранения — лишний шаг, а незаметно
        // потерянная приватная настройка хуже любого лишнего шага.
        .onChange(of: visibleToOthers) { _, _ in persist() }
        .onChange(of: plateVisible) { _, _ in persist() }
        .onChange(of: mapVisible) { _, _ in persist() }
        .onChange(of: photosVisible) { _, _ in persist() }
    }

    private func nav(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            Text(AppStrings.vehicleWhoSees(l))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(c.text)
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

    private func axis(_ title: String, _ hint: String,
                      isOn: Binding<Bool>, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(AppTheme.accent)
            }
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func loadState() {
        guard let v = vehicle else { return }
        visibleToOthers = v.visibleToOthers
        plateVisible = v.plateVisible
        mapVisible = v.mapVisible
        photosVisible = v.photosVisible
        loaded = true
    }

    private func persist() {
        // Пока состояние не прочитано, писать нечего: иначе первый же
        // `onChange` от инициализации затёр бы сохранённое умолчаниями.
        guard loaded else { return }
        settings.updateVehicleVisibility(
            id: vehicleId,
            visibleToOthers: visibleToOthers,
            plateVisible: plateVisible,
            mapVisible: mapVisible,
            photosVisible: photosVisible
        )
    }
}
