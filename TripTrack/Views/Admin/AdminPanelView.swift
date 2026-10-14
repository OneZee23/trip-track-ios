import SwiftUI

/// «Админка» (0.9.0) — решение владельца 14 окт 2026: «смотреть и управлять
/// внутренне, под своим аккаунтом», в приложении, «смотреть + флаги».
///
/// Открывается листом из настроек, тем же способом, что «Приватность»
/// (`PrivacySettingsView`), и только у аккаунта с `is_admin`. Права решает
/// СЕРВЕР на каждом запросе (`ADMIN_ONLY`); строка в настройках — лишь вход,
/// а не защита.
///
/// Порядок — от главного вопроса к служебному: сколько людей и PRO, кто
/// именно купил, что Apple присылала, и последним — флаги, которые трогают
/// раз в неделю.
struct AdminPanelView: View {
    @StateObject private var model = AdminModel()

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(spacing: 0) {
            navRow(c, l)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.failed {
                        failure(c, l)
                    }
                    if let summary = model.summary {
                        summaryCard(summary, c, l)
                    } else if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    if model.summary != nil {
                        subscriptionsSection(c, l)
                        eventsSection(c, l)
                        flagsSection(c, l)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.load() }
        }
        .background(c.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await model.load() }
        .accessibilityIdentifier("admin_panel")
    }

    // MARK: - Шапка

    private func navRow(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(alignment: .center) {
            Text(AppStrings.adminPanelTitle(l))
                .font(.inter(22, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                SheetCloseCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.closeSheet(l))
            .accessibilityIdentifier("admin_close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func failure(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.adminLoadFailed(l))
                .font(.inter(14, weight: .semibold))
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.load() }
            } label: {
                Text(AppStrings.retry(l))
                    .font(.inter(14, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Сводка

    /// Одно главное число — PRO сейчас; остальное тише. Владелец открывает
    /// экран ради вопроса «кто купил», а не ради всего сразу.
    private func summaryCard(_ s: AdminSummary, _ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(s.proActive)")
                    .font(.inter(40, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(c.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.adminProActive(l))
                        .font(.inter(15, weight: .bold))
                        .foregroundStyle(c.text)
                    Text(AppStrings.adminProSplit(l, trial: s.proTrial, paid: s.proPaid))
                        .font(AppType.meta)
                        .foregroundStyle(c.textSecondary)
                }
            }
            Divider().overlay(c.border)
            HStack(alignment: .top, spacing: 10) {
                stat("\(s.accounts)", AppStrings.adminAccounts(l), c)
                stat("\(s.accountsNew7d)", AppStrings.adminNew7d(l), c)
                stat("\(s.accountsActive7d)", AppStrings.adminActive7d(l), c)
            }
            Text(AppStrings.adminTripsLine(l, trips: s.trips, manual: s.tripsManual))
                .font(AppType.meta)
                .foregroundStyle(c.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("admin_summary")
    }

    private func stat(_ value: String, _ caption: String, _ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppType.statValue)
                .tracking(AppType.statValueTracking)
                .monospacedDigit()
                .foregroundStyle(c.text)
            Text(caption)
                .font(AppType.meta)
                .foregroundStyle(c.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Подписки

    private func subscriptionsSection(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        section(AppStrings.adminSubscriptions(l), c) {
            if model.subscriptions.isEmpty {
                empty(c, l)
            } else {
                ForEach(Array(model.subscriptions.enumerated()), id: \.element.id) { index, sub in
                    if index > 0 { Divider().overlay(c.border).padding(.leading, 16) }
                    subscriptionRow(sub, c, l)
                }
            }
        }
    }

    /// Строка — «Год · пробная · до 18 окт», под ней хвост транзакции, язык,
    /// возраст аккаунта и поездки: этого хватает, чтобы узнать подписку в
    /// письме Apple, и не хватает, чтобы узнать человека.
    private func subscriptionRow(_ s: AdminSubscription, _ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(headline(s, l))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                statusDot(s)
            }
            Text(details(s, l))
                .font(AppType.meta)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("admin_subscription")
    }

    private func headline(_ s: AdminSubscription, _ l: LanguageManager.Language) -> String {
        if s.status == "unattached" { return AppStrings.adminUnattached(l) }
        var parts = [s.isYearly ? AppStrings.adminYearly(l) : AppStrings.adminMonthly(l),
                     s.isTrial ? AppStrings.adminTrial(l) : AppStrings.adminPaid(l)]
        if let end = s.expiresAt { parts.append(AppStrings.adminUntil(l, date: Self.day(end, l))) }
        return parts.joined(separator: " · ")
    }

    private func details(_ s: AdminSubscription, _ l: LanguageManager.Language) -> String {
        var parts = ["…\(s.txTail)", Self.dayTime(s.createdAt, l)]
        if s.isAdmin { parts.append(AppStrings.adminYou(l)) }
        if let language = s.language { parts.append(language.uppercased()) }
        if let since = s.accountCreatedAt { parts.append(AppStrings.adminAccountSince(l, date: Self.day(since, l))) }
        if s.attached { parts.append("\(s.trips) \(AppStrings.nounTrips(l, s.trips))") }
        if s.status != "unattached", !s.autoRenew { parts.append(AppStrings.adminRenewOff(l)) }
        return parts.joined(separator: " · ")
    }

    /// Цвет — только состоянию, и только трём: живая, на исходе (продление
    /// выключено или льготный период), закончилась. Зелёный здесь — тот же
    /// «хорошо», что у дистанции на странице поездки.
    private func statusDot(_ s: AdminSubscription) -> some View {
        let color: Color
        switch s.status {
        case "active" where s.autoRenew: color = AppTheme.green
        case "active", "grace": color = AppTheme.accent
        case "unattached": color = AppTheme.blue
        default: color = AppTheme.colors(for: scheme).textTertiary
        }
        return Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }

    // MARK: - События

    private func eventsSection(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        section(AppStrings.adminEvents(l), c) {
            if model.events.isEmpty {
                empty(c, l)
            } else {
                ForEach(Array(model.events.prefix(20).enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider().overlay(c.border).padding(.leading, 16) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text([event.type, event.subtype].compactMap { $0 }.joined(separator: " / "))
                            .font(.inter(14, weight: .semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text([event.txTail.map { "…\($0)" }, Self.dayTime(event.at, l), event.outcome]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(AppType.meta)
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Флаги

    private func flagsSection(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            section(AppStrings.adminFlags(l), c) {
                ForEach(Array(model.flags.enumerated()), id: \.element.id) { index, flag in
                    if index > 0 { Divider().overlay(c.border).padding(.leading, 16) }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flag.name)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(c.text)
                            if flag.enabled == nil {
                                Text(AppStrings.adminDefault(l))
                                    .font(AppType.meta)
                                    .foregroundStyle(c.textSecondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if model.savingFlag == flag.name { ProgressView().controlSize(.small) }
                        Toggle(flag.name, isOn: Binding(
                            get: { flag.enabled ?? false },
                            set: { value in Task { await model.setFlag(flag.name, enabled: value) } }
                        ))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .disabled(model.savingFlag != nil)
                        .accessibilityIdentifier("admin_flag_\(flag.name)")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
            }
            Text(AppStrings.adminFlagsFootnote(l))
                .font(AppType.meta)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Общее

    private func section<Content: View>(
        _ title: String, _ c: AppTheme.Colors, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppType.section)
                .foregroundStyle(c.text)
                .padding(.leading, 2)
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(cornerRadius: 16)
        }
    }

    private func empty(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        Text(AppStrings.adminNothingYet(l))
            .font(AppType.body)
            .foregroundStyle(c.textSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let dayFormatters = LocalizedDateFormatter.templates("dMMM")
    private static let dayTimeFormatters = LocalizedDateFormatter.templates("dMMMHHmm")

    private static func day(_ date: Date, _ l: LanguageManager.Language) -> String {
        dayFormatters[l]?.string(from: date) ?? ""
    }

    private static func dayTime(_ date: Date, _ l: LanguageManager.Language) -> String {
        dayTimeFormatters[l]?.string(from: date) ?? ""
    }
}
