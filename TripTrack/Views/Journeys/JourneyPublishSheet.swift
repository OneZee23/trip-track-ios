import SwiftUI

/// Лист публикации путешествия (S5): что именно откроется людям.
///
/// Кнопка считает ТОЛЬКО поездки, которые публикация ОТКРОЕТ — плечи, уже
/// публичные сами по себе, не в счёте (`journeyPublishButton(count:)`
/// получает `privateLegs.count`, а не общее число плеч). Короткий список
/// (≤4 плеч, типичный случай) рисуется без прокрутки и сжимается по
/// содержимому; длинный уходит в `ScrollView` с потолком высоты — лист
/// сборки путешествия (0.6.6) один раз уже перерастал экран и прятал кнопку
/// под нижним краем, когда никто не поставил границу (см. `legsList`).
struct JourneyPublishSheet: View {
    let title: String
    /// Плечи, которые публикация переведёт из приватных в публичные.
    let privateLegs: [Trip]
    /// Плечи путешествия, которые публичны уже сейчас — не меняются, но
    /// человеку сказано, что они есть.
    let alreadyPublic: Int
    let onConfirm: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(alignment: .leading, spacing: 14) {
            header(c, l)
            Text(AppStrings.journeyPublishIntro(l, title: title))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !privateLegs.isEmpty {
                legsList(c, l)
            }
            if alreadyPublic > 0 {
                Text(AppStrings.journeyPublishAlreadyPublic(l, count: alreadyPublic))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            confirmButton(l)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text(AppStrings.cancel(l))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        // `.accessibilityElement(children: .contain)` FIRST: a bare
        // `.accessibilityIdentifier` on a plain container has no element of
        // its own to attach to, so it silently overwrites every child
        // button's identifier instead (measured: X, «Publish N», Cancel all
        // three reported as `journey_publish_sheet`, and the real
        // `journey_publish_confirm` id vanished). `.contain` gives the
        // VStack its own accessibility node without hiding its children.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journey_publish_sheet")
        .contentSizedSheet(background: c.card)
    }

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 10) {
            Text(AppStrings.journeyPublishTitle(l))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.close(l))
        }
    }

    /// Короткий список (типичный случай — одно-два плеча) рисуется голым
    /// `VStack`, БЕЗ `ScrollView`.
    ///
    /// У `ScrollView` нет натуральной высоты по содержимому: `.frame(maxHeight:
    /// 320)` не СЖИМАЕТ его к меньшему, а растягивает ДО 320 всегда, и
    /// `contentSizedSheet` снаружи меряет уже раздутый лист — на пять плеч
    /// потолок пуст ровно так же, как на одно. Замерено снимком: лист
    /// вытягивался почти во весь экран с пустотой перед кнопкой, совсем не
    /// компактный S5. Прокрутка нужна только когда список ДЕЙСТВИТЕЛЬНО
    /// длинный — тот же потолок, что у `JourneyComposerSheet.candidateList`,
    /// но включается только за порогом.
    @ViewBuilder
    private func legsList(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        if privateLegs.count <= 4 {
            VStack(alignment: .leading, spacing: 10) {
                legRows(c, l)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    legRows(c, l)
                }
            }
            .frame(maxHeight: 320)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func legRows(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        ForEach(privateLegs) { trip in
            JourneyLegRow(trip: trip, subtitle: subtitle(trip, l), language: l) {
                EmptyView()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func confirmButton(_ l: LanguageManager.Language) -> some View {
        let text = privateLegs.isEmpty
            ? AppStrings.journeyPublishButtonNoLegs(l)
            : AppStrings.journeyPublishButton(l, count: privateLegs.count)
        return Button {
            Haptics.tap()
            onConfirm()
            dismiss()
        } label: {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journey_publish_confirm")
    }

    /// «12 сен · 480 км · сейчас приватная» — дата и расстояние экран
    /// собирает сам, `JourneyLegRow` печатает готовую строку.
    private func subtitle(_ trip: Trip, _ l: LanguageManager.Language) -> String {
        let day = ProfileDateFormat.dayMonth(trip.startDate, lang: l)
        let km = Measure.distance(metres: trip.distance, unit: distanceUnit, lang: l, style: .grouped)
        return "\(day) · \(km) · \(AppStrings.journeyLegPrivateNow(l))"
    }
}
