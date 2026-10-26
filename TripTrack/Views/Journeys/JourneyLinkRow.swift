import SwiftUI

/// «Часть путешествия «Грузия» · 6 дней ›» — строка, которая ведёт из поездки
/// в путешествие, где она плечо.
///
/// Одна на два места: карточку в ленте и экран поездки. До 0.9.2 она жила
/// только в ленте, и поездка, открытая из профиля, о своём путешествии не
/// говорила ничего — из неё нельзя было в него попасть (владелец на 0.9.2
/// (96), 26 окт 2026, чужая поездка «Sydney → West Hoxton»).
struct JourneyLinkRow: View {
    let title: String?
    let startDate: Date
    let endDate: Date?
    let onTap: () -> Void
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(Self.text(title: title, startDate: startDate, endDate: endDate, lang: lang.language))
                    .font(.inter(12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }

    /// Имя: у клиента не всегда есть плечи, чтобы собрать имя по умолчанию,
    /// как это делает `JourneyTitle` на самом экране путешествия, поэтому
    /// пустое имя падает на `AppStrings.journeyWord`.
    static func text(title: String?, startDate: Date, endDate: Date?,
                     lang: LanguageManager.Language) -> String {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let days = JourneyWindow.days(startDate: startDate, endDate: endDate)
        return AppStrings.journeyPartOf(lang, title: (name?.isEmpty == false ? name : nil) ?? AppStrings.journeyWord(lang))
            + " · \(days) \(AppStrings.nounDays(lang, days))"
    }
}
