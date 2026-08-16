#if DEBUG
import SwiftUI
import StoreKit

/// Debug-only surface for the donation tract probe. Never ships: the whole
/// file is inside `#if DEBUG`, as is the settings row that presents it.
///
/// Copy is hardcoded Russian on purpose — `AppStrings` is for strings that
/// ship, and the dev rows above this one already set that precedent.
struct TipJarDebugView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var jar = TipJarService.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            CustomNavBar(title: "Проба доната", showsBack: false) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    NavCircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            .environment(\.navBarInSheet, true)

            ScrollView {
                VStack(spacing: 14) {
                    statusCard(c)
                    actionsCard(c)
                    if let report = jar.report {
                        reportCard(c, text: report)
                    }
                    footnote(c)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .background(c.bg.ignoresSafeArea())
        .task { await jar.load() }
    }

    // MARK: - Cards

    private func statusCard(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Продукт", TipJarService.tipID, c)
            row("Сторфронт", jar.storefront ?? "—", c)
            row("Название", jar.product?.displayName ?? "—", c)
            row("Цена", jar.product?.displayPrice ?? "—", c)
            row("Валюта", jar.product?.priceFormatStyle.currencyCode ?? "—", c)
            row("Состояние", phaseText, c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func actionsCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                Task { await jar.load() }
            } label: {
                actionLabel("Загрузить продукт заново", filled: false, c: c)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.action()
                Task { await jar.buy() }
            } label: {
                actionLabel("Купить", filled: true, c: c)
            }
            .buttonStyle(.plain)
            .disabled(jar.product == nil || jar.phase == .purchasing)
            .opacity(jar.product == nil || jar.phase == .purchasing ? 0.45 : 1)
        }
    }

    private func reportCard(_ c: AppTheme.Colors, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ПОСЛЕДНЯЯ ТРАНЗАКЦИЯ")
                .font(.inter(11, weight: .semibold))
                .foregroundStyle(c.textSecondary)

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(c.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    /// The point the probe is most likely to be over-read: a green purchase
    /// here is not evidence that money can arrive.
    private func footnote(_ c: AppTheme.Colors) -> some View {
        Text("""
        Покупка в окружении xcode или sandbox не двигает денег, не попадает \
        в Sales and Trends и не влияет на выплату. Локальный .storekit вообще \
        не ходит на серверы Apple — его чек любая серверная проверка отвергнет. \
        Настоящие цифры живут в App Store Connect → Payments and Financial Reports.
        """)
        .font(.inter(12))
        .foregroundStyle(c.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: - Bits

    private func row(_ key: String, _ value: String, _ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.inter(13))
                .foregroundStyle(c.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.inter(13, weight: .medium))
                .foregroundStyle(c.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionLabel(_ title: String, filled: Bool, c: AppTheme.Colors) -> some View {
        Text(title)
            .font(.inter(15, weight: .semibold))
            .foregroundStyle(filled ? Color.white : AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(filled ? AppTheme.accent : AppTheme.accentBg)
            )
    }

    private var phaseText: String {
        switch jar.phase {
        case .idle:            return "—"
        case .loading:         return "загружаю продукт…"
        case .ready:           return "готов к покупке"
        case .purchasing:      return "покупка идёт…"
        case .succeeded:       return "покупка прошла"
        case .cancelled:       return "отменена пользователем"
        case .deferred:        return "ожидает подтверждения (Ask To Buy)"
        case .failed(let why): return "ошибка: \(why)"
        }
    }
}
#endif
