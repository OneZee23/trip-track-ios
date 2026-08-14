import SwiftUI

/// Profile bio editor (Figma 1873:6873): Отмена / О себе / Готово over a
/// three-line box, a hint + counter row. Sibling of `UsernameEditorSheet` and
/// `NameEditorSheet` — same chrome, same detent, same keyboard behaviour, so
/// the three read as one editor wearing three fields.
struct AboutEditorSheet: View {
    let initialText: String
    let onSave: (String) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var validationError: String?
    @FocusState private var isFocused: Bool

    private static let maxLength = 140
    /// Fixed, and that matters: a box that grows with its content feeds its own
    /// height back into the measured detent, and the sheet inflates to full
    /// screen the moment you drag it — with no way back down. Same trap
    /// `TripEditSheet.notesHeight` documents. 100 is the canon inner box
    /// (1873:6891), ~4 lines at 17, which 140 characters cannot outrun.
    private static let boxHeight: CGFloat = 100
    /// TextEditor lays its text out 5pt in from its own frame. Cancelling that
    /// puts the first glyph on the card's 16pt gutter, in line with the hint
    /// and counter underneath it.
    private static let editorInset: CGFloat = 5

    // MARK: - Body

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)

            header(c)

            field(c)
                .padding(.horizontal, 16)

            helperRow(c)
                .animation(.easeInOut(duration: 0.15), value: validationError)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
        }
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.hidden)
        .onAppear {
            text = initialText
            validationError = nil
            // A beat, or the sheet's own presentation transition eats the
            // keyboard's — same delay NameEditorSheet needs.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = true
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.aboutTitle(lang.language))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)

            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Text(AppStrings.cancel(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Haptics.action()
                    commit()
                } label: {
                    Text(AppStrings.done(lang.language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityIdentifier("about_editor_done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func field(_ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(c.text)
                .scrollContentBackground(.hidden)
                .frame(height: Self.boxHeight)
                // Leading only: pulling the trailing edge out too would run the
                // text under the clear button.
                .padding(.leading, -Self.editorInset)
                .focused($isFocused)
                    // Stock iOS blue against an all-orange screen.
                    .tint(AppTheme.accent)
                .onChange(of: text) { _, new in
                    // Hard cap rather than a complaint on «Готово»: finding out
                    // there was a limit costs you the tail of what you wrote.
                    if new.count > Self.maxLength {
                        text = String(new.prefix(Self.maxLength))
                    }
                    validationError = validate(text)
                }
                .accessibilityLabel(AppStrings.aboutTitle(lang.language))
                .accessibilityIdentifier("about_editor_field")

            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(c.textTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
}
                .buttonStyle(.plain)
                // Nudged onto the first line's optical centre; the editor's own
                // ~8pt top inset sits the text below its frame.
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(c.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor(c), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: validationError)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    @ViewBuilder
    private func helperRow(_ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let err = validationError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(err)
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(AppTheme.red)
            } else {
                Text(AppStrings.aboutHint(lang.language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text("\(text.count)/\(Self.maxLength)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(text.count >= Self.maxLength ? AppTheme.red : c.textTertiary)
        }
    }

    // MARK: - Derived state

    private var canSave: Bool {
        // An empty bio is a legitimate edit — clearing what you wrote is the
        // only way to take it back, so this deliberately does not require text.
        ContentFilter.sanitize(text) != ContentFilter.sanitize(initialText)
            && validationError == nil
    }

    private func borderColor(_ c: AppTheme.Colors) -> Color {
        if validationError != nil { return AppTheme.red }
        return isFocused ? AppTheme.accent : c.borderBright
    }

    // MARK: - Validation

    private func validate(_ value: String) -> String? {
        // `.tripNote`, not `.displayName`: a bio describes a person rather than
        // naming one, so the identity rules (mixed script, repeat runs,
        // punctuation floods) would reject ordinary copy like «Люблю BMW».
        // What survives is the objectionable-content check App Review asks for.
        ContentFilter.validate(ContentFilter.sanitize(value), field: .tripNote, language: lang.language)
    }

    private func commit() {
        // Sanitize once more on the way out so what we send up matches what was
        // on screen — a paste can land invisible characters between the last
        // `onChange` and the tap on «Готово».
        let sanitized = ContentFilter.sanitize(text)
        guard validationError == nil else { return }
        onSave(sanitized)
        dismiss()
    }
}
