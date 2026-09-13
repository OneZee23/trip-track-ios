import SwiftUI

/// Лист переименования места — поле и «Сохранить», в `contentSizedSheet`,
/// как остальные листы дома. Пустое имя — снова безымянное.
struct PlaceRenameSheet: View {
    let name: String?
    let onSave: (String?) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @State private var text: String
    @FocusState private var focused: Bool

    init(name: String?, onSave: @escaping (String?) -> Void) {
        self.name = name
        self.onSave = onSave
        _text = State(initialValue: name ?? "")
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.placeRename(l))
                .font(.inter(18, weight: .bold)).foregroundStyle(c.text)
            TextField(AppStrings.placeNamePlaceholder(l), text: $text)
                .font(.inter(16))
                .padding(12)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
            Button {
                save()
            } label: {
                Text(AppStrings.save(l))
                    .font(.inter(15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .contentSizedSheet(background: c.card)
        .onAppear { focused = true }
    }

    private func save() {
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
