import SwiftUI

/// Fuel-price currency picker (Figma «06 · Авто · Валюта цены топлива (пикер)»).
///
/// Reports back through a binding and touches nothing else: the currency is a
/// property of ONE vehicle — a second car can live in a second country — so the
/// caller decides where the pick lands, and the app-wide default is left alone.
struct FuelCurrencyPickerSheet: View {
    @Binding var selectedSymbol: String

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private static let rowHeight: CGFloat = 46
    private static let rowSpacing: CGFloat = 2
    /// Nine rows: enough that the list reads as scrollable, short enough that
    /// the whole sheet still clears the bottom of a small phone.
    private static let maxVisibleRows = 9

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(c: c, l: l)
            currencyList(c: c, l: l)
            Text(AppStrings.currencyPickerHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Nav Row

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            Text(AppStrings.currencyPickerTitle(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    SheetCloseCircle()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("currency_picker_close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - List

    private func currencyList(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // A fixed height, not a flexible one: `contentSizedSheet` measures what
        // it wraps and a ScrollView reports whatever height it was offered, so
        // an unbounded list would have the detent feeding its own measurement.
        ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(FuelCurrency.allCases, id: \.self) { currency in
                    row(currency, c: c, l: l)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Self.listHeight)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    private static var listHeight: CGFloat {
        let rows = CGFloat(min(FuelCurrency.allCases.count, maxVisibleRows))
        return rows * rowHeight + max(0, rows - 1) * rowSpacing
    }

    private func row(_ currency: FuelCurrency, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let isSelected = currency.symbol == selectedSymbol
        return Button {
            Haptics.selection()
            selectedSymbol = currency.symbol
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(currency.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? AppTheme.accent : c.text)
                    .frame(width: 32, height: 32)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 9))

                Text(currency.name(l))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                Text(currency.code)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)

                // Reserved rather than conditional: a checkmark that exists only
                // on the selected row pushes that row's ISO code out of the
                // column every other row lines up in.
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accent.opacity(0.08) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("currency_row_\(currency.code)")
    }
}
