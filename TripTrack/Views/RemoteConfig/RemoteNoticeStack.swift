import SwiftUI

/// Карточки, которые приходят с сервера (0.9.0): «Обновите приложение» и
/// объявления для этого места. Обе меняются без новой версии и без ревью —
/// `RemoteConfigStore`.
///
/// Карточка, а не системный диалог: правило «Dialogs» в CLAUDE.md. И не
/// модальная: человек, пришедший записать поездку, не обязан сначала читать
/// новости. Закрытие запоминается по `id` объявления (а у обновления — по
/// версии, до которой просят обновиться): новый текст — новый id — новая
/// карточка.
struct RemoteNoticeStack: View {
    let placement: RemoteConfig.Announcement.Placement
    /// Карточку обновления показывает одно место, иначе она висела бы дважды.
    var showsUpdate: Bool = false
    /// Поля вокруг стопки — только когда в ней есть карточки: пустая стопка
    /// не должна сдвигать экран ни на точку.
    var outerPadding = EdgeInsets()

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = RemoteConfigStore.shared
    @AppStorage("remoteConfig.dismissed") private var dismissedRaw = ""

    private var dismissed: Set<String> { Set(dismissedRaw.split(separator: "\n").map(String.init)) }

    private func dismiss(_ key: String) {
        Haptics.tap()
        var set = dismissed
        set.insert(key)
        // Только последние сорок: старые id никогда больше не придут.
        dismissedRaw = Array(set).suffix(40).joined(separator: "\n")
    }

    var body: some View {
        let config = store.config
        let version = AppVersion.current
        let need = showsUpdate ? config.updateNeed(appVersion: version) : nil
        let updateKey = "update:\(config.update.required ?? config.update.recommended ?? "")"
        let notices = config.announcements(for: placement, appVersion: version, now: Date())
            .filter { !dismissed.contains("announcement:\($0.id)") }

        let showsUpdateCard = need.map { $0 == .required || !dismissed.contains(updateKey) } ?? false
        if showsUpdateCard || !notices.isEmpty {
        VStack(spacing: 12) {
            if let need, showsUpdateCard {
                card(
                    title: AppStrings.remoteUpdateTitle(lang.language),
                    body: config.update.message?.text(lang.language) ?? AppStrings.remoteUpdateBody(lang.language),
                    actionLabel: AppStrings.remoteUpdateAction(lang.language),
                    action: { openURL(Self.appStoreURL) },
                    onClose: need == .required ? nil : { dismiss(updateKey) },
                    identifier: "remote_update_card")
            }
            ForEach(notices) { notice in
                card(
                    title: notice.title.text(lang.language),
                    body: notice.body.text(lang.language),
                    actionLabel: notice.action?.label.text(lang.language),
                    action: notice.action.map { action in { openURL(action.url) } },
                    onClose: { dismiss("announcement:\(notice.id)") },
                    identifier: "remote_announcement_\(notice.id)")
            }
        }
        .padding(outerPadding)
        }
    }

    static let appStoreURL = URL(string: "itms-apps://apps.apple.com/app/id6760650361")!

    @ViewBuilder
    private func card(title: String, body: String, actionLabel: String?, action: (() -> Void)?,
                      onClose: (() -> Void)?, identifier: String) -> some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.interScaled(16, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(c.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -12)
                    .padding(.vertical, -14)
                    .accessibilityLabel(AppStrings.close(lang.language))
                }
            }
            Text(body)
                .font(.interScaled(14, relativeTo: .subheadline))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button {
                    Haptics.tap()
                    action()
                } label: {
                    Text(actionLabel)
                        .font(.interScaled(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, actionLabel == nil ? 14 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
