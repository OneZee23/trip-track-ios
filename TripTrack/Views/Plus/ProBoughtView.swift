import SwiftUI

/// «Ты в PRO» — состояние 9 матрицы 0.8.4, и состояние 36б, когда покупка
/// случилась из листа ручной поездки.
///
/// Экран отвечает на «и что дальше»: без него человек остаётся с подпиской и
/// без дороги к тому, что купил. Поэтому здесь ТРИ вещи, и все три
/// обязательны: когда начнутся списания, где искать купленное и что значок
/// PRO у имени появился сам — его видят чужие, а человек его не выбирал.
struct ProBoughtView: View {
    /// Откуда пришла покупка. `manualTrip` — из листа вписанной поездки, и
    /// тогда единственная кнопка возвращает ТУДА, со всем набранным.
    enum Origin: Equatable { case storefront, manualTrip }

    let origin: Origin
    let data: ProDemoData
    /// Дата окончания периода. `nil` — StoreKit ещё не сказал; строки даты
    /// тогда нет вовсе, а не «до —».
    let until: Date?
    /// В пробном периоде. Тогда строка обязана назвать и дату, и цену после.
    let isTrial: Bool
    /// Цена года напечатанной витриной.
    let yearlyPrice: String?
    let onPickBackground: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.proBoughtTitle(l))
                    .font(AppType.title)
                    .kerning(AppType.titleTracking)
                    .foregroundStyle(c.text)
                if let period = periodLine(l) {
                    Text(period)
                        .font(AppType.body)
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)
            .padding(.vertical, 12)

            ProDemoPreviewView(preview: .profileStrip, data: data)
                .frame(height: 140)
                .frame(maxWidth: .infinity)

            Text(AppStrings.proBoughtText(l))
                .font(AppType.body)
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)

            Text(AppStrings.proBoughtBadge(l))
                .font(AppType.meta)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Spacer(minLength: 16)

            buttons(c, l)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(c.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_bought")
    }

    @ViewBuilder
    private func buttons(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        switch origin {
        case .manualTrip:
            // Одна кнопка, и ведёт она ТУДА, откуда пришли: человек набирал
            // поездку, а не витрину, и выбор фона здесь был бы подменой темы.
            primary(AppStrings.proBoughtBackToTrip(l), action: onClose)
                .accessibilityIdentifier("pro_bought_back_to_trip")
        case .storefront:
            primary(AppStrings.proBoughtPickBg(l), action: onPickBackground)
                .accessibilityIdentifier("pro_bought_pick_bg")
            Button {
                Haptics.tap()
                onClose()
            } label: {
                Text(AppStrings.commonLater(l))
                    .font(AppType.action)
                    .foregroundStyle(c.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("pro_bought_later")
        }
    }

    private func primary(
        _ title: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.action()
            action()
        } label: {
            Text(title)
                .font(AppType.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent)
                )
        }
        .buttonStyle(PressableCardStyle())
    }

    /// «Неделя бесплатно до 6 окт., потом 19,99 € в год» или «До 29 сент. 2027,
    /// продлится автоматически».
    ///
    /// `nil`, когда даты нет: StoreKit отвечает на `currentEntitlements`
    /// асинхронно, и «До —» хуже, чем ничего. Цена у строки триала
    /// обязательна: человек только что нажал «бесплатно», и когда начнутся
    /// списания, он должен прочитать это здесь, а не в App Store.
    private func periodLine(_ l: LanguageManager.Language) -> String? {
        guard let until else { return nil }
        guard let date = Self.formatters[l]?.string(from: until) else { return nil }
        if isTrial {
            guard let yearlyPrice else { return nil }
            return AppStrings.proBoughtTrial(l, date: date, price: yearlyPrice)
        }
        return AppStrings.proBoughtPaid(l, date: date)
    }

    /// По одному форматтеру на язык, собранные один раз: `DateFormatter`
    /// дорогой, а экран его пересоздавал бы на каждую перерисовку.
    private static let formatters = LocalizedDateFormatter.templates("dMMMyyyy")
}
