import SwiftUI

/// Что нужно карточке, чтобы нарисовать себя — посчитано ДО `body`, как у
/// `RiddleHintCardModel` по соседству.
///
/// Кнопка «Написать» ведёт по ТОЙ ЖЕ почте, что строка «Написать автору» в
/// профиле (`ProfileSettingsSheet.authorEmail`), а не заводит вторую —
/// один ящик, одно место, которое о нём знает. `feedbackURL` — опциональный,
/// а не готовый `URL`: если маршрут когда-нибудь пропадёт (пустой адрес),
/// карточка сама падает на один только «Понятно», и тест проверяет обе ветки
/// без обращения к `body`.
struct AtlasBetaSheetModel {
    let feedbackURL: URL?

    static func make(feedbackAddress: String? = ProfileSettingsSheet.authorEmail) -> AtlasBetaSheetModel {
        guard let feedbackAddress, !feedbackAddress.isEmpty,
              let url = URL(string: "mailto:\(feedbackAddress)")
        else {
            return AtlasBetaSheetModel(feedbackURL: nil)
        }
        return AtlasBetaSheetModel(feedbackURL: url)
    }
}

/// «Атлас в бете» — дом-карточка, открытая тапом по `AtlasBetaChip`.
///
/// Не `.alert`, не `.confirmationDialog` — см. «Dialogs» в CLAUDE.md: лист
/// размером ровно в своё содержимое (`.contentSizedSheet`), собран в
/// `MyMapView`.
struct AtlasBetaSheet: View {
    let model: AtlasBetaSheetModel
    let onDismiss: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.atlasBetaTitle(lang.language))
                .font(.inter(19, weight: .heavy))
                .foregroundStyle(c.text)

            Text(AppStrings.atlasBetaBody(lang.language))
                .font(.inter(14))
                .lineSpacing(3)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                if let feedbackURL = model.feedbackURL {
                    Button {
                        Haptics.tap()
                        openURL(feedbackURL)
                    } label: {
                        Text(AppStrings.writeAuthor(lang.language))
                            .font(.inter(15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("atlas_beta_feedback")
                }

                Button {
                    Haptics.tap()
                    onDismiss()
                } label: {
                    Text(AppStrings.ok(lang.language))
                        .font(.inter(15, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("atlas_beta_dismiss")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_beta_sheet")
    }
}
