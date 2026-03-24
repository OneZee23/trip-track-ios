import SwiftUI

struct NotesEditorView: View {
    @Binding var text: String
    let onSave: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        NavigationStack {
            TextEditor(text: $text)
                .font(.system(size: 16))
                .foregroundStyle(c.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(c.cardAlt)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(16)
            .background(c.bg)
            .navigationTitle(AppStrings.notes(lang.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text(lang.language == .ru ? "Отмена" : "Cancel")
                            .foregroundStyle(c.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onSave() } label: {
                        Text(lang.language == .ru ? "Сохранить" : "Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
    }
}
