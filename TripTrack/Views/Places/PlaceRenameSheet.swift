import SwiftUI

/// Лист переименования места (макет «Места» 0.8.1, S5): поле, подсказка про
/// адрес, «Вернуть название по адресу» и пара кнопок. В `contentSizedSheet`,
/// как остальные листы дома.
///
/// Пустое имя — снова безымянное: стереть название это законный ответ, а не
/// ошибка ввода, и «Сохранить» на пустом поле остаётся живым.
struct PlaceRenameSheet: View {
    let name: String?
    /// Имя от геокодера — подпись под полем и цель кнопки «Вернуть название
    /// по адресу». `nil` — кэш геокодера этого места не знает, и обе строки
    /// не рисуются вовсе: обещать «адрес» и не показать его хуже молчания.
    var address: String?
    let onSave: (String?) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @State private var text: String
    @FocusState private var focused: Bool

    init(name: String?, address: String? = nil, onSave: @escaping (String?) -> Void) {
        self.name = name
        self.address = address
        self.onSave = onSave
        _text = State(initialValue: name ?? "")
    }

    var body: some View {
        let l = lang.language
        VStack(alignment: .leading, spacing: 14) {
            header(l)
            field(l)
            Text(hint(l))
                .font(AppType.meta)
                .foregroundStyle(AtlasTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -4)
            if let address, text.trimmingCharacters(in: .whitespaces) != address {
                useAddressButton(address, l)
            }
            buttons(l)
        }
        .padding(.horizontal, AtlasTheme.sideInset)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .contentSizedSheet(background: AtlasTheme.background)
        .onAppear { focused = true }
        .accessibilityIdentifier("place_rename_sheet")
    }

    private func header(_ l: LanguageManager.Language) -> some View {
        HStack(spacing: 12) {
            Text(AppStrings.placeRenameTitle(l))
                .font(AppType.sheetTitle)
                .foregroundStyle(AtlasTheme.ink)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AtlasTheme.ink)
                    .frame(width: AtlasTheme.controlSize, height: AtlasTheme.controlSize)
                    .background(AtlasTheme.searchBackground, in: Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(AppStrings.close(l))
        }
    }

    private func field(_ l: LanguageManager.Language) -> some View {
        HStack(spacing: 4) {
            TextField(AppStrings.placeNamePlaceholder(l), text: $text)
                .font(AppType.unit)
                .foregroundStyle(AtlasTheme.ink)
                .tint(AtlasTheme.accent)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
                .accessibilityIdentifier("place_rename_field")
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(AtlasTheme.handle)
                        .frame(width: AtlasTheme.controlSize, height: AtlasTheme.controlSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.calendarClearFilter(l))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 56)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AtlasTheme.separator, lineWidth: 1)
        }
    }

    private func hint(_ l: LanguageManager.Language) -> String {
        guard let address else { return AppStrings.placeRenameHint(l) }
        return AppStrings.placeRenameHintAddress(l, address: address)
    }

    private func useAddressButton(_ address: String, _ l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            text = address
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 14, weight: .semibold))
                Text(AppStrings.placeRenameUseAddress(l)).font(AppType.itemTitle)
            }
            .foregroundStyle(AtlasTheme.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("place_rename_use_address")
    }

    private func buttons(_ l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                sheetButtonLabel(AppStrings.cancel(l), fill: AtlasTheme.searchBackground, ink: AtlasTheme.ink)
            }
            .buttonStyle(PressableCardStyle())
            Button {
                save()
            } label: {
                sheetButtonLabel(AppStrings.save(l), fill: AtlasTheme.accent, ink: .white)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("place_rename_save")
        }
    }

    private func sheetButtonLabel(_ title: String, fill: Color, ink: Color) -> some View {
        Text(title)
            .font(AppType.button)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(fill, in: RoundedRectangle(cornerRadius: AtlasTheme.statRadius, style: .continuous))
    }

    private func save() {
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
