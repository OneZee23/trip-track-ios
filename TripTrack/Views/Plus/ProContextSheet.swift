import SwiftUI

/// Контекстное предложение — состояние 11 матрицы 0.8.4.
///
/// Лист появляется САМ, и это единственное место в платной части, где
/// приложение обращается первым. Поэтому у него ровно два ответа и ни одного
/// третьего: «Подробнее о PRO» и «Не сейчас». Крестика нет — закрытие жестом
/// вниз считается тем же «Не сейчас», и цена у него та же (два подряд дают
/// паузу 90 дней), иначе правило частоты обходилось бы свайпом.
///
/// Высота — ЧИСЛОМ (`ProLayout.contextSheet(titleLines:)`), не измерением:
/// правило проекта, купленное дважды сломанным экраном «Атласа».
struct ProContextSheet: View {
    let moment: ProOfferMoment
    let data: ProDemoData
    /// Продаёт ли лист. `false` — витрина не продаёт платное, и тогда это
    /// ИЗВЕЩЕНИЕ с одной кнопкой (состояние 17а).
    let sells: Bool
    /// «Подробнее о PRO» / «Продлить» — ведёт на страницу той функции, которую
    /// момент обещал.
    let onOpen: (PlusFeature) -> Void
    /// «Не сейчас» или закрытие жестом. Считается отказом.
    let onDecline: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            ProDemoPreviewView(preview: preview, data: data)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .padding(.top, 25)

            VStack(spacing: 4) {
                Text(Self.title(moment, l))
                    .font(.inter(20, weight: .semibold))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(text(l))
                    .font(AppType.body)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            Spacer(minLength: 16)

            Button {
                Haptics.action()
                if sells {
                    onOpen(ProContextOffer.feature(for: moment))
                } else {
                    // Вести некуда: витрина не продаёт. Кнопка закрывает лист
                    // и отказом НЕ считается — человек не отказывался, ему
                    // сообщили.
                    onDecline()
                }
            } label: {
                Text(primaryTitle(l))
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
            .accessibilityIdentifier("pro_ctx_primary")

            if sells {
                Button {
                    Haptics.tap()
                    onDecline()
                } label: {
                    Text(AppStrings.proCtxNotNow(l))
                        .font(AppType.action)
                        .foregroundStyle(c.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("pro_ctx_not_now")
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(c.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_context_sheet")
    }

    /// Превью той функции, которую момент обещал. Нарисовать здесь другую
    /// значило бы показать одно, а продать другое.
    private var preview: ProDemoPreview {
        ProDemoContent.preview(for: ProContextOffer.feature(for: moment),
                               hasVehicle: data.vehicleTitle != nil,
                               hasTrips: !data.route.isEmpty)
    }

    /// Заголовок момента. `static`, потому что его спрашивает и высота листа
    /// (`ProOfferHost.sheetHeight`) — до того, как лист построен: число строк
    /// считается по ДЛИНЕ этой самой строки, и второй копии её быть не должно.
    static func title(
        _ moment: ProOfferMoment, _ l: LanguageManager.Language
    ) -> String {
        switch moment {
        case .tenTrips: return AppStrings.proCtxM1Title(l)
        case .oneMonth: return AppStrings.proCtxM3Title(l)
        case .expired:  return AppStrings.proCtxM4Title(l)
        }
    }

    private func text(_ l: LanguageManager.Language) -> String {
        switch moment {
        case .tenTrips: return AppStrings.proCtxM1Text(l)
        case .oneMonth: return AppStrings.proCtxM3Text(l)
        case .expired:  return AppStrings.proCtxM4Text(l)
        }
    }

    /// «Продлить» у того, у кого PRO было, «Подробнее о PRO» у остальных, и
    /// «Понятно» там, где вести некуда.
    private func primaryTitle(_ l: LanguageManager.Language) -> String {
        guard sells else { return AppStrings.commonOk(l) }
        return moment == .expired
            ? AppStrings.proCtxRenew(l)
            : AppStrings.proCtxMore(l)
    }
}
