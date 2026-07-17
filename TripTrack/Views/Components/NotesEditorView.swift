import SwiftUI

/// «Описание» editor sheet (Figma 532:119): custom Отмена / Описание /
/// Сохранить header, plain text area, «N / 500» counter bottom-right.
/// The 500-char cap is UI-level (Figma); `ContentFilter` still validates
/// on save. Legacy notes longer than 500 keep their original length as
/// the cap so opening the editor never silently truncates them.
struct NotesEditorView: View {
    @Binding var text: String
    let onSave: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool
    @State private var charLimit = 500

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            // Header row (below the sheet grabber).
            ZStack {
                Text(AppStrings.descriptionSection(lang.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)
                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text(AppStrings.cancel(lang.language))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(c.textSecondary)
                    }
                    Spacer()
                    Button {
                        Haptics.action()
                        onSave()
                    } label: {
                        Text(lang.language == .ru ? "Сохранить" : "Save")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            TextEditor(text: $text)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                Spacer()
                Text("\(text.count) / \(charLimit)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(text.count >= charLimit ? AppTheme.red : c.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(c.card)
        .onAppear {
            charLimit = max(500, text.count)
            editorFocused = true
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > charLimit {
                text = String(newValue.prefix(charLimit))
            }
        }
    }
}
